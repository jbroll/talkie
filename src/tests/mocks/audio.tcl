# Mock Audio module
package provide audio 1.0

namespace eval ::audio {
    variable mock_energy_value 10.0
}

# Mock energy calculation - returns configurable value
proc ::audio::energy {data format} {
    variable mock_energy_value
    return $mock_energy_value
}

# Test utility to set mock energy value
proc ::audio::set_mock_energy {value} {
    variable mock_energy_value
    set mock_energy_value $value
}