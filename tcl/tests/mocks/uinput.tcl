# Mock uinput module
package provide uinput 1.0

namespace eval ::uinput {
    variable mock_typed_text ""
}

proc ::uinput::type {text} {
    variable mock_typed_text
    append mock_typed_text $text
}

# Test utility to get and clear typed text
proc ::uinput::get_typed_text {} {
    variable mock_typed_text
    return $mock_typed_text
}

proc ::uinput::clear_typed_text {} {
    variable mock_typed_text
    set mock_typed_text ""
}