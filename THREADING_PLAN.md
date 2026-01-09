# Dedicated Audio Processing Thread - Implementation Plan

## Problem Statement

Despite the existing worker thread for STT processing, audio can still be missed because the **main Tcl event loop** handles audio callbacks. When the main thread is busy with GUI updates, file watching, or other events, the ring buffer can overflow.

### Current Architecture

```
PortAudio RT Thread          Main Tcl Event Loop           STT Worker Thread
───────────────────          ───────────────────           ─────────────────

pa_rt_callback()             tcl_notify_proc()             worker::process()
     │                            │                              │
     │ rb_write()                 │ rb_read() ≤200ms             │
     │ (ring buffer)              │                              │
     │                            │                              │
     └──notify────────────────────► audio_callback()             │
       (socketpair)               │    │                         │
                                  │    ├─ energy calc            │
                                  │    ├─ VAD                    │
                                  │    └─ process-async ─────────►
                                  │                         ─────► vosk
                                  │                              │
                                  │ ◄───── result-async ─────────┘
                                  │
                                  │ parse_and_display_result()
                                  │ GUI updates
                                  │ type_async → Output Thread
```

### Identified Bottlenecks

| Component | Issue | Impact |
|-----------|-------|--------|
| Main thread audio callback | Competes with GUI, file watching | Ring buffer overflow |
| Ring buffer | 500ms capacity, silent overflow | Audio loss |
| 200ms read cap | Falls behind if event loop slow | Accumulating lag |
| Output thread queue | Unbounded, 20ms per character | Latency growth |
| uinput typing | Blocking usleep() calls | Output thread blocked |

### Evidence

1. **Ring buffer overflows** - Now visible via Buf: health indicator
2. **Main thread contention** - GUI updates, config dialog, file watchers all run in same event loop
3. **Reset was blocking** - Fixed in commit 6caa1c5 (now async)

## Proposed Architecture

Move audio processing entirely off the main thread:

```
PortAudio RT      Audio Processing      STT Worker       Main Thread
Thread            Thread (NEW)          Thread           (GUI only)
──────────        ────────────────      ──────────       ───────────

pa_rt_callback    audio_thread_proc     vosk_worker      Tk event loop
     │                 │                     │                │
     │ rb_write()      │ rb_read()           │                │
     │                 │ (blocking OK)       │                │
     │                 │                     │                │
     └──notify────────►│ energy calc         │                │
                       │ VAD                 │                │
                       │ buffer mgmt         │                │
                       │                     │                │
                       └─ process-async ─────►│               │
                                              │ vosk process  │
                                              │               │
                                              └─ result ──────► display
                                                               │
                         NO BLOCKING          NO BLOCKING      │
                         FROM MAIN THREAD                      │
```

### Key Benefits

1. **Complete isolation** - Audio never waits for GUI
2. **Predictable timing** - Audio thread has dedicated CPU time
3. **Larger safety margin** - Can increase ring buffer without main thread concern
4. **Simpler main thread** - Only handles GUI and result display

## Implementation Plan

### Phase 1: Audio Thread Infrastructure

#### 1.1 Create Audio Thread Module (`audio_thread.tcl`)

```tcl
package require Thread

namespace eval ::audio_thread {
    variable tid ""
    variable main_tid ""
    variable running 0
}

proc ::audio_thread::start {main_tid_arg} {
    variable tid
    variable main_tid $main_tid_arg

    set tid [thread::create {
        package require Thread

        namespace eval ::audio_thread::worker {
            variable main_tid ""
            variable stream ""
            variable running 0
            variable audio_buffer_list {}
            variable last_speech_time 0
            variable this_speech_time 0
        }

        thread::wait
    }]

    # Transfer worker procedures
    thread::send $tid [list namespace eval ::audio_thread::worker { ... }]

    return $tid
}
```

#### 1.2 Worker Thread Audio Loop

```tcl
proc ::audio_thread::worker::run {stream_name} {
    variable running 1
    variable stream $stream_name

    while {$running} {
        # Block waiting for audio data (up to 200ms)
        set data [read_audio_blocking $stream 200]

        if {$data ne ""} {
            process_audio_chunk $data
        }
    }
}

proc ::audio_thread::worker::process_audio_chunk {data} {
    variable audio_buffer_list
    variable last_speech_time
    variable this_speech_time
    variable main_tid

    # Energy calculation
    set audiolevel [audio::energy $data int16]

    # Update UI (async, non-blocking)
    thread::send -async $main_tid [list set ::audiolevel $audiolevel]

    # VAD
    set timestamp [clock milliseconds]
    set is_speech [is_speech_local $audiolevel $last_speech_time]
    thread::send -async $main_tid [list set ::is_speech $is_speech]

    # Transcription logic (same as current audio_callback)
    if {$::transcribing} {
        # ... lookback buffer management ...
        # ... process-async to STT worker ...
    }
}
```

#### 1.3 Blocking Audio Read

Modify `pa.tcl` to support blocking read from ring buffer:

```c
// New C function: blocking read with timeout
static int rb_read_blocking(SPSC_Ring *rb, unsigned char *dst,
                            unsigned int n, int timeout_ms) {
    int waited = 0;
    while (rb_available(rb) < n && waited < timeout_ms) {
        usleep(1000);  // 1ms sleep
        waited++;
    }
    return rb_read(rb, dst, rb_available(rb) < n ? rb_available(rb) : n);
}
```

Or use the existing socketpair notification with `select()` timeout.

### Phase 2: Decouple from Main Thread

#### 2.1 Remove tcl_notify_proc Callback

Current: PortAudio notifies main thread via Tcl file handler
New: Audio thread polls/blocks on ring buffer directly

```tcl
# In audio_thread::worker::init
proc init {stream_ctx_ptr} {
    # Get direct access to ring buffer
    # No Tcl file handler needed
}
```

#### 2.2 Thread-Safe Global State

Variables accessed from multiple threads need synchronization:

```tcl
# Read-only from audio thread (set by main thread)
# - ::transcribing
# - ::config(*)

# Write from audio thread, read by main thread
# - ::audiolevel (atomic, no lock needed)
# - ::is_speech (atomic, no lock needed)
# - ::buffer_health (atomic)

# Complex state - use thread::send
# - Result delivery to main thread
```

#### 2.3 Modify pa.tcl for Direct Thread Access

Option A: Pass ring buffer pointer to audio thread
Option B: Create separate audio thread in C code
Option C: Use thread-safe queue instead of Tcl file handler

Recommended: **Option A** - minimal C changes, Tcl thread reads ring buffer directly.

### Phase 3: Output Thread Improvements

#### 3.1 Add Queue Depth Monitoring

```tcl
namespace eval ::output {
    variable queue_depth 0
    variable max_queue_depth 0
}

proc ::output::type_async {text} {
    variable worker_tid
    variable queue_depth

    if {$text eq ""} return

    incr queue_depth
    thread::send -async $worker_tid [list ::output::worker::type_text_tracked $text]
}

# In worker thread
proc ::output::worker::type_text_tracked {text} {
    # ... type text ...

    # Notify main thread of completion
    thread::send -async $main_tid {incr ::output::queue_depth -1}
}
```

#### 3.2 Optimize uinput Typing

Current: 20ms per character (two usleep calls)
Target: 5-10ms per character

```c
// Reduce delay, rely on kernel buffering
static void emit_key_click(int key) {
    emit_event(EV_KEY, key, 1);
    emit_event(EV_KEY, key, 0);
    emit_sync(typing_delay_us / 2);  // Half the delay
}

static void uinput_type_char(char c) {
    // ... emit keys ...
    // Remove second usleep - sync already has delay
}
```

#### 3.3 Batch Character Output

For longer text, batch multiple characters before sync:

```c
static void uinput_type_string_fast(const char *str) {
    for (int i = 0; str[i]; i++) {
        emit_char_no_sync(str[i]);
        if (i % 4 == 3) {  // Sync every 4 chars
            emit_sync(typing_delay_us);
        }
    }
    emit_sync(typing_delay_us);  // Final sync
}
```

### Phase 4: Enhanced Health Monitoring

#### 4.1 Comprehensive Health Status

```tcl
# Global health state
set ::health_status {
    ring_buffer_overflows 0
    ring_buffer_fill_pct 0
    stt_queue_depth 0
    output_queue_depth 0
    audio_thread_alive 1
    stt_worker_alive 1
    output_worker_alive 1
}

proc update_health_display {} {
    # Aggregate health into single indicator
    set problems 0

    if {$::health_status(ring_buffer_overflows) > 0} { incr problems }
    if {$::health_status(stt_queue_depth) > 10} { incr problems }
    if {$::health_status(output_queue_depth) > 20} { incr problems }
    if {!$::health_status(audio_thread_alive)} { incr problems 10 }

    set ::buffer_health [expr {min($problems, 2)}]
}
```

#### 4.2 Ring Buffer Fill Percentage

Add to pa.tcl:

```c
// In StreamObjCmd "stats" handler
unsigned int fill = rb_available(&ctx->ring);
unsigned int capacity = ctx->ring.size;
int fill_pct = (fill * 100) / capacity;
Tcl_DictObjPut(interp, d, Tcl_NewStringObj("fill_pct", -1),
               Tcl_NewIntObj(fill_pct));
```

#### 4.3 Thread Liveness Monitoring

```tcl
proc check_thread_health {} {
    # Check audio thread
    if {[catch {thread::send $::audio_thread::tid {expr 1}} result]} {
        set ::health_status(audio_thread_alive) 0
        puts "CRITICAL: Audio thread died!"
    }

    # Check STT worker
    if {[catch {thread::send $::engine::worker_tid {expr 1}} result]} {
        set ::health_status(stt_worker_alive) 0
        puts "CRITICAL: STT worker died!"
    }

    after 5000 check_thread_health
}
```

## Migration Strategy

### Step 1: Non-Breaking Preparation
- Add ring buffer fill percentage to stats
- Add output queue depth tracking
- Enhance health monitoring UI

### Step 2: Audio Thread (Feature Flag)
- Implement audio_thread.tcl
- Add config option: `use_audio_thread`
- Test with flag enabled, fall back to current behavior

### Step 3: Optimize Output Thread
- Reduce uinput delays
- Add queue depth monitoring
- Implement backpressure (drop old text if queue too deep)

### Step 4: Remove Legacy Path
- Remove tcl_notify_proc callback mode
- Audio thread becomes default
- Update THREADING_FINAL.md

## Testing Plan

### Unit Tests
1. Audio thread starts/stops cleanly
2. Ring buffer read from separate thread works
3. Thread-safe variable updates work
4. Output queue depth tracking accurate

### Integration Tests
1. Full transcription flow with audio thread
2. Start/stop transcription rapidly
3. Engine switching with audio thread active
4. Suspend/resume with audio thread

### Stress Tests
1. High speech rate (rapid continuous talking)
2. Slow STT model (simulate backlog)
3. Fast typing target (vim, IDE)
4. GUI stress (rapid config dialog open/close)

### Metrics to Track
- Ring buffer overflow count (should be 0)
- Ring buffer fill percentage (should stay <50%)
- STT queue depth (should stay <5)
- Output queue depth (should stay <10)
- End-to-end latency (speech to typed output)

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Thread deadlock | Low | High | Async-only communication, no locks |
| Audio thread crash | Low | High | Liveness monitoring, auto-restart |
| Race conditions | Medium | Medium | Thread-safe patterns, atomic variables |
| Performance regression | Low | Medium | Benchmark before/after |
| Tcl Thread package bugs | Low | High | Test on target Tcl version |

## Effort Estimate

| Phase | Description | Effort |
|-------|-------------|--------|
| Phase 1 | Audio thread infrastructure | 3-4 hours |
| Phase 2 | Decouple from main thread | 2-3 hours |
| Phase 3 | Output thread improvements | 2 hours |
| Phase 4 | Enhanced health monitoring | 1-2 hours |
| Testing | All phases | 3-4 hours |
| **Total** | | **11-15 hours** |

## Success Criteria

1. **Zero buffer overflows** under normal use
2. **Ring buffer fill <30%** average
3. **STT queue depth <3** average
4. **Output queue depth <5** average
5. **No UI freezes** during heavy transcription
6. **<500ms latency** from speech end to typed output

## References

- `THREADING_FINAL.md` - Current worker thread implementation
- `src/engine.tcl` - STT worker thread code
- `src/output.tcl` - Output worker thread code
- `src/pa/pa.tcl` - PortAudio ring buffer implementation
- `src/audio.tcl` - Current audio callback (to be moved to audio thread)
