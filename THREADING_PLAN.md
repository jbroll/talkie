# Multi-Threading Implementation Plan for Talkie

## Problem Statement

Currently, the audio callback (runs every ~100ms) synchronously calls speech-to-text processing:
- **Vosk (critcl)**: Direct blocking C function calls (50-200ms)
- **Coprocess engines**: Blocking pipe I/O (100-300ms)

When STT processing exceeds the 100ms callback interval, we **miss audio buffers**, causing gaps in transcription.

## Solution: Tcl Thread Package with Dedicated STT Worker

### Architecture Overview

```
Main Thread (Event Loop)          STT Worker Thread
─────────────────────              ─────────────────
Audio Callback (100ms)             
    ↓                              
Recognizer Proxy                   
    | process-async() ──────────→  Worker Process
    |                               ├─ Vosk C calls (blocking OK)
    |                               ├─ Coprocess I/O (blocking OK)
    |                               └─ Send result back
    |                              
    | ←─────────────────────────── thread::send -async
    ↓                              
parse_and_display_result           
    ↓                              
UI Updates                         
```

### Key Design Decisions

1. **Single Worker Thread** (not a pool)
   - Recognizer is stateful and order-dependent
   - Simplest architecture with no ordering issues

2. **Thread Boundary in Engine Layer**
   - Keep audio.tcl focused on capture/VAD
   - Minimal changes to audio callback logic

3. **Async Result Delivery**
   - Worker uses `thread::send -async` back to main thread
   - Preserves thread-safety for UI updates

4. **Binary Audio Passing**
   - Pass chunks as Tcl bytearray via `thread::send -async`
   - ~3KB per 100ms chunk is negligible overhead

## Implementation Steps

### Phase 1: Engine Layer Threading (engine.tcl)

#### 1.1 Add Thread Support
```tcl
package require Thread

namespace eval ::engine {
    variable worker_tid ""
    variable main_tid ""
}
```

#### 1.2 Create Worker Thread
In `engine::initialize`:
```tcl
# Save main thread ID
set main_tid [thread::id]

# Create worker thread
set worker_tid [thread::create {
    namespace eval ::engine::worker {
        variable engine_name ""
        variable engine_type ""
        variable recognizer ""
        variable main_tid ""
    }
    
    # Worker will wait for commands
    thread::wait
}]

# Initialize worker
thread::send $worker_tid [list ::engine::worker::init \
    $main_tid $engine_name $engine_type $model_path $::device_sample_rate]
```

#### 1.3 Worker Initialization
```tcl
# Executed in worker thread
proc ::engine::worker::init {main_tid_arg engine_name_arg engine_type_arg model_path sample_rate} {
    variable main_tid $main_tid_arg
    variable engine_name $engine_name_arg
    variable engine_type $engine_type_arg
    variable recognizer
    
    if {$engine_type eq "critcl"} {
        # Load Vosk in worker thread
        package require vosk
        vosk::set_log_level -1
        set model [vosk::load_model -path $model_path]
        set recognizer [$model create_recognizer -rate $sample_rate]
    } elseif {$engine_type eq "coprocess"} {
        # Start coprocess in worker thread
        source coprocess.tcl
        set response [::coprocess::start $engine_name $command $model_path $sample_rate]
        # Parse response, check for errors, etc.
    }
}
```

#### 1.4 Worker Methods
```tcl
# Process audio chunk (blocking OK in worker)
proc ::engine::worker::process {chunk} {
    variable recognizer
    variable engine_type
    variable engine_name
    variable main_tid
    
    if {$engine_type eq "critcl"} {
        set result [$recognizer process $chunk]
    } else {
        set result [::coprocess::process $engine_name $chunk]
    }
    
    # Send result back to main thread asynchronously
    thread::send -async $main_tid [list ::audio::parse_and_display_result $result]
}

# Get final result (blocking OK in worker)
proc ::engine::worker::final {} {
    variable recognizer
    variable engine_type
    variable engine_name
    variable main_tid
    
    if {$engine_type eq "critcl"} {
        set result [$recognizer final-result]
    } else {
        set result [::coprocess::final $engine_name]
    }
    
    thread::send -async $main_tid [list ::audio::parse_and_display_result $result]
}

# Reset recognizer
proc ::engine::worker::reset {} {
    variable recognizer
    variable engine_type
    variable engine_name
    
    if {$engine_type eq "critcl"} {
        $recognizer reset
    } else {
        ::coprocess::reset $engine_name
    }
}

# Cleanup
proc ::engine::worker::close {} {
    variable recognizer
    variable engine_type
    variable engine_name
    
    if {$engine_type eq "critcl"} {
        catch {rename $recognizer ""}
    } else {
        ::coprocess::stop $engine_name
    }
}
```

#### 1.5 Create Recognizer Proxy Command
```tcl
proc ::engine::create_async_recognizer_cmd {engine_name worker_tid} {
    set cmd_name "::recognizer_async_${engine_name}"
    
    proc $cmd_name {method args} [format {
        set worker_tid %s
        
        switch $method {
            "process-async" {
                set chunk [lindex $args 0]
                thread::send -async $worker_tid [list ::engine::worker::process $chunk]
            }
            "final-async" {
                thread::send -async $worker_tid {::engine::worker::final}
            }
            "reset" {
                thread::send $worker_tid {::engine::worker::reset}
            }
            "close" {
                thread::send $worker_tid {::engine::worker::close}
                thread::release $worker_tid
                rename %s ""
            }
            default {
                error "Unknown method: $method"
            }
        }
    } $worker_tid $cmd_name]
    
    return $cmd_name
}
```

### Phase 2: Audio Layer Changes (audio.tcl)

#### 2.1 Modified Audio Callback
Replace synchronous `process_buffered_audio` with async processing:

```tcl
proc ::audio::audio_callback {stream_name timestamp data} {
    variable this_speech_time
    variable last_speech_time
    variable audio_buffer_list
    
    try {
        set audiolevel [audio::energy $data int16]
        set ::audiolevel $audiolevel
        
        set is_speech [threshold::is_speech $audiolevel $last_speech_time]
        set ::is_speech $is_speech
        
        if {$::transcribing} {
            set lookback_frames [expr {int($::config(lookback_seconds) * 10 + 0.5)}]
            lappend audio_buffer_list $data
            set audio_buffer_list [lrange $audio_buffer_list end-$lookback_frames end]
            
            set recognizer [::engine::recognizer]
            if {$recognizer eq ""} {
                set audio_buffer_list {}
                return
            }
            
            # Rising edge of speech - send lookback buffer
            if {$is_speech && !$last_speech_time} {
                set this_speech_time $timestamp
                foreach chunk $audio_buffer_list {
                    $recognizer process-async $chunk
                }
                set last_speech_time $timestamp
            } elseif {$last_speech_time} {
                # Ongoing speech - send only current chunk
                $recognizer process-async $data
                set last_speech_time $timestamp
                
                # Check for silence timeout
                if {$last_speech_time + $::config(silence_seconds) < $timestamp} {
                    $recognizer final-async
                    
                    set speech_duration [expr {$last_speech_time - $this_speech_time}]
                    if {$speech_duration <= $::config(min_duration)} {
                        after idle [partial_text ""]
                        print THRS-SHORTS $speech_duration
                    }
                    
                    set last_speech_time 0
                    set audio_buffer_list {}
                }
            }
        }
    } on error message {
        puts "audio callback: $message\n$::errorInfo"
    }
}
```

#### 2.2 Remove Old Synchronous Processing
Delete the old `process_buffered_audio` proc - no longer needed.

### Phase 3: Lifecycle Management

#### 3.1 Startup
```tcl
proc ::audio::initialize {} {
    if {![::engine::initialize]} {
        puts "Failed to initialize speech engine"
        return false
    }
    
    start_audio_stream
    # ... rest of initialization
}
```

#### 3.2 Cleanup
```tcl
proc ::engine::cleanup {} {
    variable recognizer_cmd
    variable worker_tid
    variable engine_name
    
    if {$engine_name eq ""} return
    
    puts "Cleaning up $engine_name engine..."
    
    if {$recognizer_cmd ne ""} {
        catch {$recognizer_cmd close}
        set recognizer_cmd ""
    }
    
    if {$worker_tid ne ""} {
        catch {thread::release $worker_tid}
        set worker_tid ""
    }
    
    puts "Cleanup complete"
}
```

#### 3.3 Stop Transcription
```tcl
proc ::audio::stop_transcription {} {
    variable last_speech_time
    variable audio_buffer_list
    
    set ::transcribing 0
    state_save $::transcribing
    
    # Reset worker thread recognizer
    set recognizer [::engine::recognizer]
    if {$recognizer ne ""} {
        catch {$recognizer reset}
    }
    
    set last_speech_time 0
    set audio_buffer_list {}
}
```

## Testing Plan

### Unit Tests
1. **Thread creation/cleanup**
   - Verify worker thread is created on init
   - Verify thread is released on cleanup
   - Test multiple init/cleanup cycles

2. **Audio chunk passing**
   - Send test chunks to worker
   - Verify chunks arrive intact
   - Test with various chunk sizes

3. **Result delivery**
   - Mock worker responses
   - Verify async callback to main thread
   - Test partial and final results

### Integration Tests
1. **End-to-end transcription**
   - Feed real audio through system
   - Verify no dropped buffers
   - Compare transcription quality to current version

2. **Load testing**
   - Rapid speech input
   - Verify queue doesn't grow unbounded
   - Test with slow STT models

3. **Engine switching**
   - Test Vosk (critcl) threading
   - Test coprocess engine threading
   - Verify no cross-contamination

## Risk Mitigation

### 1. Vosk Thread Safety
- Create Vosk recognizer entirely in worker thread
- Never call Vosk from main thread
- Verify package can be loaded in worker thread

### 2. Coprocess Channel Ownership
- Open pipes only in worker thread
- Configure channels (binary/line mode) in worker
- Never share channels across threads

### 3. Backlog Growth
- Monitor worker queue depth (add metric)
- If backlog grows, consider:
  - Coalescing chunks (e.g., 300ms instead of 100ms)
  - Dropping old pre-speech frames
  - Warning user about slow model

### 4. Lifecycle Races
- Guard all `thread::send` with existence checks
- Use `catch` around worker posts
- Handle worker death gracefully

## Performance Expectations

### Current (Synchronous)
- Audio callback blocked: 50-300ms
- Dropped buffers: Common during heavy processing
- UI freezes: Occasional

### After Threading
- Audio callback duration: <5ms (no blocking)
- Dropped buffers: None (unless audio hardware issue)
- UI responsiveness: Always smooth
- Latency increase: None (results arrive asynchronously)

## Effort Estimate

- **Phase 1**: Engine layer threading - 2-3 hours
- **Phase 2**: Audio layer changes - 1-2 hours  
- **Phase 3**: Lifecycle management - 1 hour
- **Testing & debugging**: 2-3 hours
- **Total**: 6-9 hours

## Future Enhancements

1. **Backpressure handling**
   - Queue depth monitoring
   - Automatic frame coalescing under load

2. **Multiple recognizers**
   - One worker per recognizer
   - Parallel language detection

3. **Job cancellation**
   - Cancel in-flight processing when switching models
   - Use `thread::tpool` for advanced job control

4. **Metrics**
   - Track worker queue depth
   - Monitor processing time per chunk
   - Detect real-time factor (RTF > 1.0 = falling behind)
