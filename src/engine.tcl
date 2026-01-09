# engine.tcl - Hybrid speech engine abstraction layer
# Supports both in-process (critcl) and coprocess engines

package require Thread

source coprocess.tcl

namespace eval ::engine {
    variable recognizer_cmd ""
    variable engine_name ""
    variable worker_tid ""
    variable main_tid ""

    # Engine registry - central configuration
    variable engine_registry
    array set engine_registry {
        vosk,command      ""
        vosk,type         "critcl"
        vosk,model_dir    "vosk"
        vosk,model_config "vosk_modelfile"

        sherpa,command      "engines/sherpa_wrapper.sh"
        sherpa,type         "coprocess"
        sherpa,model_dir    "sherpa-onnx"
        sherpa,model_config "sherpa_modelfile"

        faster-whisper,command      "engines/faster_whisper_wrapper.sh"
        faster-whisper,type         "coprocess"
        faster-whisper,model_dir    "faster-whisper"
        faster-whisper,model_config "faster_whisper_modelfile"
    }

    # Check if engine is registered
    proc is_registered {engine_name} {
        variable engine_registry
        return [info exists engine_registry($engine_name,type)]
    }

    # Get engine property
    proc get_property {engine_name property} {
        variable engine_registry
        set key "${engine_name},${property}"
        if {[info exists engine_registry($key)]} {
            return $engine_registry($key)
        }
        return ""
    }

    # Worker thread procedures (executed in worker thread context)
    namespace eval ::engine::worker {
        variable engine_name ""
        variable engine_type ""
        variable recognizer ""
        variable main_tid ""
        variable script_dir ""
        
        proc init {main_tid_arg engine_name_arg engine_type_arg model_path sample_rate script_dir_arg} {
            variable main_tid $main_tid_arg
            variable engine_name $engine_name_arg
            variable engine_type $engine_type_arg
            variable recognizer
            variable script_dir $script_dir_arg
            
            lappend auto_path "$::env(HOME)/.local/lib/tcllib2.0"
            lappend auto_path [file join $script_dir pa lib pa]
            lappend auto_path [file join $script_dir vosk lib vosk]
            lappend auto_path [file join $script_dir audio lib audio]
            lappend auto_path [file join $script_dir uinput lib uinput]
            
            package require json
            
            if {$engine_type eq "critcl"} {
                package require vosk
                if {[info commands vosk::set_log_level] ne ""} {
                    vosk::set_log_level -1
                }
                
                if {[file exists $model_path]} {
                    set model [vosk::load_model -path $model_path]
                    set recognizer [$model create_recognizer -rate $sample_rate -alternatives 1]
                    return [json::dict2json {status ok message "Vosk worker initialized"}]
                } else {
                    return [json::dict2json [list status error error "Model not found: $model_path"]]
                }
            } elseif {$engine_type eq "coprocess"} {
                source [file join $script_dir coprocess.tcl]
                
                set cmd_path [file join $script_dir [lindex $model_path 0]]
                set model_path_only [lindex $model_path 1]
                
                set response [::coprocess::start $engine_name $cmd_path $model_path_only $sample_rate]
                return $response
            } else {
                return [json::dict2json [list status error error "Unknown engine type: $engine_type"]]
            }
        }
        
        proc process {chunk} {
            variable recognizer
            variable engine_type
            variable engine_name
            variable main_tid
            
            try {
                if {$engine_type eq "critcl"} {
                    set result [$recognizer process $chunk]
                } else {
                    set result [::coprocess::process $engine_name $chunk]
                }
                
                if {$result ne ""} {
                    thread::send -async $main_tid [list ::audio::parse_and_display_result $result]
                }
            } on error {err info} {
                puts stderr "Worker process error: $err"
            }
        }
        
        proc final {} {
            variable recognizer
            variable engine_type
            variable engine_name
            variable main_tid
            
            try {
                if {$engine_type eq "critcl"} {
                    set result [$recognizer final-result]
                } else {
                    set result [::coprocess::final $engine_name]
                }
                
                if {$result ne ""} {
                    thread::send -async $main_tid [list ::audio::parse_and_display_result $result]
                }
            } on error {err info} {
                puts stderr "Worker final error: $err"
            }
        }
        
        proc reset {} {
            variable recognizer
            variable engine_type
            variable engine_name
            
            try {
                if {$engine_type eq "critcl"} {
                    $recognizer reset
                } else {
                    ::coprocess::reset $engine_name
                }
            } on error {err info} {
                puts stderr "Worker reset error: $err"
            }
        }
        
        proc close {} {
            variable recognizer
            variable engine_type
            variable engine_name
            
            try {
                if {$engine_type eq "critcl"} {
                    if {$recognizer ne "" && [info commands $recognizer] ne ""} {
                        catch {rename $recognizer ""}
                    }
                } else {
                    ::coprocess::stop $engine_name
                }
            } on error {err info} {
                puts stderr "Worker close error: $err"
            }
        }
    }
    
    # Create async recognizer proxy command
    proc create_async_recognizer_cmd {engine_name worker_tid} {
        set cmd_name "::recognizer_async_${engine_name}"
        
        proc $cmd_name {method args} [format {
            set worker_tid %s
            
            if {![catch {thread::exists $worker_tid} exists] && !$exists} {
                return
            }
            
            switch $method {
                "process-async" {
                    set chunk [lindex $args 0]
                    catch {thread::send -async $worker_tid [list ::engine::worker::process $chunk]}
                }
                "final-async" {
                    catch {thread::send -async $worker_tid {::engine::worker::final}}
                }
                "reset" {
                    catch {thread::send -async $worker_tid {::engine::worker::reset}}
                }
                "close" {
                    catch {thread::send $worker_tid {::engine::worker::close}}
                    catch {thread::release $worker_tid}
                    rename %s ""
                }
                default {
                    error "Unknown method: $method"
                }
            }
        } $worker_tid $cmd_name]
        
        return $cmd_name
    }

    # Initialize engine and return recognizer command
    proc initialize {} {
        variable recognizer_cmd
        variable engine_name
        variable worker_tid
        variable main_tid

        set engine_name $::config(speech_engine)

        # Check if engine is registered
        if {![is_registered $engine_name]} {
            puts "ERROR: Unknown engine: $engine_name"
            return false
        }

        set engine_type [get_property $engine_name type]
        
        # Save main thread ID
        set main_tid [thread::id]
        
        puts "Initializing $engine_name engine (type: $engine_type) with worker thread..."

        # Create worker thread and transfer the worker namespace code
        set worker_tid [thread::create {
            namespace eval ::engine::worker {}
            thread::wait
        }]
        
        # Send the worker procedures to the worker thread
        thread::send $worker_tid [list namespace eval ::engine::worker {
            variable engine_name ""
            variable engine_type ""
            variable recognizer ""
            variable main_tid ""
            variable script_dir ""
            
            proc init {main_tid_arg engine_name_arg engine_type_arg model_path sample_rate script_dir_arg} {
                variable main_tid $main_tid_arg
                variable engine_name $engine_name_arg
                variable engine_type $engine_type_arg
                variable recognizer
                variable script_dir $script_dir_arg
                
                package require Thread
                
                if {[lsearch -exact $::auto_path "$::env(HOME)/.local/lib/tcllib2.0"] < 0} {
                    lappend ::auto_path "$::env(HOME)/.local/lib/tcllib2.0"
                }
                lappend ::auto_path [file join $script_dir pa lib pa]
                lappend ::auto_path [file join $script_dir vosk lib vosk]
                lappend ::auto_path [file join $script_dir audio lib audio]
                lappend ::auto_path [file join $script_dir uinput lib uinput]
                
                package require json
                
                if {$engine_type eq "critcl"} {
                    package require vosk
                    if {[info commands vosk::set_log_level] ne ""} {
                        vosk::set_log_level -1
                    }
                    
                    if {[file exists $model_path]} {
                        set model [vosk::load_model -path $model_path]
                        set recognizer [$model create_recognizer -rate $sample_rate -alternatives 1]
                        return [json::dict2json {status ok message "Vosk worker initialized"}]
                    } else {
                        return [json::dict2json [list status error error "Model not found: $model_path"]]
                    }
                } elseif {$engine_type eq "coprocess"} {
                    source [file join $script_dir coprocess.tcl]
                    
                    set cmd_path [file join $script_dir [lindex $model_path 0]]
                    set model_path_only [lindex $model_path 1]
                    
                    set response [::coprocess::start $engine_name $cmd_path $model_path_only $sample_rate]
                    return $response
                } else {
                    return [json::dict2json [list status error error "Unknown engine type: $engine_type"]]
                }
            }
            
            proc process {chunk} {
                variable recognizer
                variable engine_type
                variable engine_name
                variable main_tid
                
                try {
                    if {$engine_type eq "critcl"} {
                        set result [$recognizer process $chunk]
                    } else {
                        set result [::coprocess::process $engine_name $chunk]
                    }
                    
                    if {$result ne ""} {
                        thread::send -async $main_tid [list ::audio::parse_and_display_result $result]
                    }
                } on error {err info} {
                    puts stderr "Worker process error: $err"
                }
            }
            
            proc final {} {
                variable recognizer
                variable engine_type
                variable engine_name
                variable main_tid
                
                try {
                    if {$engine_type eq "critcl"} {
                        set result [$recognizer final-result]
                    } else {
                        set result [::coprocess::final $engine_name]
                    }
                    
                    if {$result ne ""} {
                        thread::send -async $main_tid [list ::audio::parse_and_display_result $result]
                    }
                } on error {err info} {
                    puts stderr "Worker final error: $err"
                }
            }
            
            proc reset {} {
                variable recognizer
                variable engine_type
                variable engine_name
                
                try {
                    if {$engine_type eq "critcl"} {
                        $recognizer reset
                    } else {
                        ::coprocess::reset $engine_name
                    }
                } on error {err info} {
                    puts stderr "Worker reset error: $err"
                }
            }
            
            proc close {} {
                variable recognizer
                variable engine_type
                variable engine_name
                
                try {
                    if {$engine_type eq "critcl"} {
                        if {$recognizer ne "" && [info commands $recognizer] ne ""} {
                            catch {rename $recognizer ""}
                        }
                    } else {
                        ::coprocess::stop $engine_name
                    }
                } on error {err info} {
                    puts stderr "Worker close error: $err"
                }
            }
        }]
        
        # Prepare model path based on engine type
        if {$engine_type eq "critcl"} {
            if {$engine_name eq "vosk"} {
                set model_path [get_model_path $::config(vosk_modelfile)]
                if {$model_path eq "" || ![file exists $model_path]} {
                    puts "ERROR: Vosk model not found"
                    catch {thread::release $worker_tid}
                    set worker_tid ""
                    return false
                }
            } else {
                puts "ERROR: Unknown critcl engine: $engine_name"
                catch {thread::release $worker_tid}
                set worker_tid ""
                return false
            }
        } elseif {$engine_type eq "coprocess"} {
            set cmd [get_property $engine_name command]
            set model_config [get_property $engine_name model_config]
            set model_dir [get_property $engine_name model_dir]

            if {$model_config ne "" && [info exists ::config($model_config)]} {
                set modelfile $::config($model_config)
                set model_path_full [file join [file dirname $::script_dir] models $model_dir $modelfile]
            } else {
                set model_path_full [file join [file dirname $::script_dir] models $model_dir]
            }
            
            set model_path [list $cmd $model_path_full]
        } else {
            puts "ERROR: Unknown engine type: $engine_type"
            catch {thread::release $worker_tid}
            set worker_tid ""
            return false
        }
        
        puts "  Worker thread: $worker_tid"
        puts "  Main thread: $main_tid"
        puts "  Model path: $model_path"
        puts "  Sample rate: $::device_sample_rate"
        
        # Initialize worker thread
        set response [thread::send $worker_tid [list ::engine::worker::init \
            $main_tid $engine_name $engine_type $model_path $::device_sample_rate $::script_dir]]
        
        # Parse response
        set response_dict [json::json2dict $response]
        
        if {![dict exists $response_dict status] || [dict get $response_dict status] ne "ok"} {
            if {[dict exists $response_dict error]} {
                puts "ERROR: Worker initialization failed: [dict get $response_dict error]"
            } else {
                puts "ERROR: Worker initialization failed: $response"
            }
            catch {thread::release $worker_tid}
            set worker_tid ""
            return false
        }
        
        puts "✓ Worker thread initialized successfully"
        if {[dict exists $response_dict message]} {
            puts "  [dict get $response_dict message]"
        }
        
        # Create async recognizer proxy
        set recognizer_cmd [create_async_recognizer_cmd $engine_name $worker_tid]
        
        return true
    }

    # Cleanup
    proc cleanup {} {
        variable recognizer_cmd
        variable engine_name
        variable worker_tid

        # Safety check - if engine_name is empty, nothing to cleanup
        if {$engine_name eq ""} {
            return
        }

        puts "Cleaning up $engine_name engine..."

        # Close recognizer proxy (will send close to worker and release thread)
        if {$recognizer_cmd ne ""} {
            catch {$recognizer_cmd close}
            set recognizer_cmd ""
        }

        # Extra safety: ensure worker thread is released
        if {$worker_tid ne ""} {
            catch {thread::release $worker_tid}
            set worker_tid ""
        }

        set engine_name ""
        puts "Cleanup complete"
    }

    # Return the recognizer command (for audio.tcl)
    proc recognizer {} {
        variable recognizer_cmd
        return $recognizer_cmd
    }

    # Get current engine name
    proc current {} {
        variable engine_name
        return $engine_name
    }
}
