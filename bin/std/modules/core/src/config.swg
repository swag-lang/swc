// Defines big endian.
public const BIG_ENDIAN = #gettag("Swag.Endian", string, "little") == "big"

// Defines windows.
public const WINDOWS = #os == Swag.TargetOs.Windows

// Defines assert.
public const ASSERT = #cfg == "debug" or #cfg == "fast-debug" or #hastag("Std.Core.Assert")
