// Defines big endian.
public const BIG_ENDIAN = #gettag("Swag.Endian", string, "little") == "big"

// Defines windows.
public const WINDOWS = #os == Swag.TargetOs.Windows

// Deprecated: use #safety(Swag.SafetyWhat.Assert) to include local safety overrides.
public const ASSERT = #safety(Swag.SafetyWhat.Assert)
