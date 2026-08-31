package Core

// ============================================================================
// VERSION HELPERS
// ============================================================================
//
// Internal Core helpers. Components never compare versions directly — they
// receive already-validated handles/registrations from Core.
// ============================================================================

// version_is_zero reports whether a Version triple is the all-zero sentinel
// used to mean "unset" / "no upper bound".
@(private)
version_is_zero :: proc(version: Version) -> bool {
	return version.major == 0 && version.minor == 0 && version.patch == 0
}

// version_compare returns -1/0/+1 comparing two versions component-wise.
@(private)
version_compare :: proc(a: Version, b: Version) -> int {
	if a.major != b.major do return a.major < b.major ? -1 : 1
	if a.minor != b.minor do return a.minor < b.minor ? -1 : 1
	if a.patch != b.patch do return a.patch < b.patch ? -1 : 1
	return 0
}

// version_in_range returns true when `version` is within
// [min_version, max_version]. max_version == 0.0.0 means "no upper bound".
@(private)
version_in_range :: proc(version: Version, min_version: Version, max_version: Version) -> bool {
	if version_compare(version, min_version) < 0 do return false
	if !version_is_zero(max_version) {
		if version_compare(version, max_version) > 0 do return false
	}
	return true
}

// version_satisfies returns true when `version` lies within the optional
// `has_min_version` / `has_max_version` window declared by a Lib_Dependency.
@(private)
version_satisfies :: proc(version: Version, dependency: Lib_Dependency) -> bool {
	if dependency.has_min_version {
		if version_compare(version, dependency.min_version) < 0 do return false
	}
	if dependency.has_max_version {
		if version_compare(version, dependency.max_version) > 0 do return false
	}
	return true
}