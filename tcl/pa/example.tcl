package require critcl
set auto_path [linsert $auto_path 0 [file join [pwd] lib]]
package require pa
Pa_Init

# simple callback that writes received audio to a file
proc my_cb {stream timestamp data} {
    puts "[$stream info]: got [string length $data] bytes at $timestamp"
    set f [open /tmp/record.raw a]
    fconfigure $f -translation binary
    puts -nonewline $f $data
    close $f
}

# open a stream (default device) 44100 Hz, 2 channels, float32
set s [pa::open_stream -device default -rate 44100 -channels 2 \
       -frames 256 -format float32 -callback my_cb]

$s start

after 5000 {
    $s stop
    puts "Stats: [$s stats]"
    $s close
    puts done
}
vwait forever
