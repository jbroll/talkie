lappend auto_path [file join [file dirname [info script]] .. lib]
package require sherpa
set v [sherpa::version]
if {$v eq ""} { puts "FAIL: empty version"; exit 1 }
puts "PASS: sherpa-onnx version = $v"
exit 0
