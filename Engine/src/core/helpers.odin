package Core

version_is_zero :: proc(version: Version) -> bool {
    return version.major == 0 && version.minor == 0 && version.patch == 0
}

version_compare :: proc(a: Version, b: Version) -> int {
   	if a.major < b.major do return -1
	if a.major > b.major do return 1

	if a.minor < b.minor do return -1
	if a.minor > b.minor do return 1

	if a.patch < b.patch do return -1
	if a.patch > b.patch do return 1
    
    return 0
}

// ============================================================================
// VERSION RANGE
// ============================================================================
//
// max_version == 0.0.0 means "no upper bound".
//
version_in_range :: proc(version: Version, min_version: Version, max_version: Version) -> bool {
	if version_compare(version, min_version) < 0 do return false
	if !version_is_zero(max_version) {
        if version_compare(version, max_version) > 0 do return false
    }
	return true
}