# PortAudio Tcl Binding (`pa` package)

This document describes the Tcl-level interface provided by the Critcl-based `pa` package, a PortAudio binding.

---

## Package

```tcl
package require pa 1.0
```

This loads and initializes PortAudio via Critcl. The package will build a shared library the first time it is loaded.

---

## Commands

### `pa::init`

```tcl
pa::init
```

Initialize PortAudio. Normally called automatically when the package is loaded. Returns `0` on success.

---

### `pa::list_devices`

```tcl
set devices [pa::list_devices]
```

Returns a list of dictionaries describing available audio devices.

Each dictionary contains:

* `index` — integer device index
* `name` — device name string
* `maxInputChannels` — number of input channels supported
* `defaultSampleRate` — default sample rate (Hz)

Example:

```tcl
foreach d [pa::list_devices] {
    puts "Device $d"
}
```

---

### `pa::open_stream`

```tcl
set s [pa::open_stream ?options?]
```

Opens an input stream. Returns the name of a new Tcl command (a *stream object command*) that controls the stream.

**Options:**

* `-device name` — device name substring or `default` (default: `default`)
* `-rate hz` — sample rate in Hz (default: `44100`)
* `-channels n` — number of input channels (default: `1`)
* `-frames n` — frames per buffer (default: `256`)
* `-format fmt` — sample format: `float32` (default) or `int16`
* `-callback script` — Tcl callback invoked when audio data arrives

---

## Stream Object Command

A stream object command is returned by `pa::open_stream`. It supports the following subcommands:

### `start`

```tcl
$s start
```

Starts audio capture.

### `stop`

```tcl
$s stop
```

Stops audio capture.

### `info`

```tcl
set info [$s info]
```

Returns a dictionary with stream parameters and stats:

* `rate` — sample rate
* `channels` — number of channels
* `framesPerBuffer` — buffer size in frames
* `overflows` — number of buffer overflows
* `underruns` — number of buffer underruns

### `close`

```tcl
$s close
```

Closes the stream, releases resources, and deletes the stream object command.

### `setcallback`

```tcl
$s setcallback script
```

Sets or replaces the Tcl callback script for audio delivery.

### `stats`

```tcl
set stats [$s stats]
```

Returns a dictionary with runtime statistics:

* `overflows`
* `underruns`

---

## Callback Signature

When audio data is available, the specified callback is invoked with:

```tcl
{callback streamName timestamp data}
```

* `streamName` — name of the stream object command
* `timestamp` — time (seconds, double) since stream start
* `data` — binary data containing raw samples

The format of `data` depends on the chosen `-format`:

* `float32` — 32-bit IEEE-754 floats (native endianness)
* `int16` — 16-bit signed integers (little-endian)

You can use `binary format` and `binary scan` to interpret the data.

---

## Example: Record 5 Seconds

```tcl
proc record_cb {s t data} {
    set f [open /tmp/test.raw a]
    fconfigure $f -translation binary
    puts -nonewline $f $data
    close $f
    puts "[$s info]: got [string length $data] bytes at $t"
}

set s [pa::open_stream -rate 44100 -channels 2 -frames 256 -format float32 -callback record_cb]
$s start

after 5000 {
    $s stop
    puts "Stats: [$s stats]"
    $s close
    puts done
}

vwait forever
```

This captures stereo float32 PCM for 5 seconds and writes it to `/tmp/test.raw`.

---

## Notes

* Only input (recording) streams are supported currently.
* Data is delivered in raw binary form; user code must interpret or save.
* Use `pa::list_devices` to enumerate audio devices.
* Stream callbacks should return quickly; heavy work should be offloaded.
* Overflows indicate the ring buffer was full and audio was dropped.
