# worker.tcl - Reusable worker thread pattern
# Provides a common abstraction for creating and managing worker threads
#
# Usage:
#   set tid [::worker::create $name $init_script]
#   ::worker::send $name {some_proc arg1 arg2}
#   ::worker::send_async $name {some_proc arg1 arg2}
#   ::worker::call $name proc_name arg1 arg2  ;# returns result
#   ::worker::destroy $name

package require Thread

namespace eval ::worker {
    variable workers {}  ;# dict: name -> {tid main_tid}

    # Create a new worker thread
    # name: unique identifier for this worker
    # namespace_script: script to eval in the worker's namespace (procs, variables)
    # Returns: thread id
    proc create {name namespace_script} {
        variable workers

        if {[dict exists $workers $name]} {
            error "Worker '$name' already exists"
        }

        set main_tid [thread::id]

        # Create worker thread
        set tid [thread::create {
            thread::wait
        }]

        # Send the namespace script to the worker
        thread::send $tid $namespace_script

        # Store worker info
        dict set workers $name [dict create tid $tid main_tid $main_tid]

        return $tid
    }

    # Get thread id for a worker
    proc tid {name} {
        variable workers
        if {![dict exists $workers $name]} {
            return ""
        }
        return [dict get $workers $name tid]
    }

    # Check if worker exists and is alive
    proc exists {name} {
        variable workers
        if {![dict exists $workers $name]} {
            return 0
        }
        set tid [dict get $workers $name tid]
        if {[catch {thread::exists $tid} result]} {
            return 0
        }
        return $result
    }

    # Send script to worker synchronously (waits for result)
    proc send {name script} {
        variable workers
        if {![dict exists $workers $name]} {
            error "Worker '$name' does not exist"
        }
        set tid [dict get $workers $name tid]
        return [thread::send $tid $script]
    }

    # Send script to worker asynchronously (fire and forget)
    proc send_async {name script} {
        variable workers
        if {![dict exists $workers $name]} {
            return
        }
        set tid [dict get $workers $name tid]
        catch {thread::send -async $tid $script}
    }

    # Call a proc in the worker with arguments (synchronous)
    proc call {name args} {
        return [send $name $args]
    }

    # Call a proc in the worker with arguments (asynchronous)
    proc call_async {name args} {
        send_async $name $args
    }

    # Destroy a worker thread
    proc destroy {name} {
        variable workers
        if {![dict exists $workers $name]} {
            return
        }

        set tid [dict get $workers $name tid]

        # Release the thread
        catch {thread::release $tid}

        # Remove from registry
        dict unset workers $name
    }

    # Get main thread id (for callbacks from worker)
    proc main_tid {name} {
        variable workers
        if {![dict exists $workers $name]} {
            return ""
        }
        return [dict get $workers $name main_tid]
    }
}

package provide worker 1.0
