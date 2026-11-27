// True when the target is big-endian, as selected by the `Swag.Endian` build tag.
public const BIG_ENDIAN = #gettag("Swag.Endian", string, "little") == "big"

// True when the target operating system is Windows.
public const WINDOWS = #os == Swag.TargetOs.Windows

// True when the build configuration enables assertions.
//
// Deprecated: write `#safety(Swag.SafetyWhat.Assert)` instead, which also honors local safety overrides.
public const ASSERT = #safety(Swag.SafetyWhat.Assert)
