#global public
#global namespace Errors

// Represents invalid format error.
struct InvalidFormatError
{
    using base: Swag.BaseError     // Embedded base state.
}

// Represents unsupported format error.
struct UnsupportedFormatError
{
    using base: Swag.BaseError     // Embedded base state.
}

// Represents bad parameter error.
struct BadParameterError
{
    using base: Swag.BaseError     // Embedded base state.
}

// Represents syntax error.
struct SyntaxError
{
    using base: Swag.BaseError     // Embedded base state.
    line, col:  u64                // Line associated with this value.
    seek:       u64                // Seek associated with this value.
}

// Represents overflow error.
struct OverflowError
{
    using base: Swag.BaseError     // Embedded base state.
}

// Represents parse incomplete error.
struct ParseIncompleteError
{
    using base: Swag.BaseError     // Embedded base state.
}

// Represents serialization error.
struct SerializationError
{
    using base: Swag.BaseError            // Embedded base state.
    field:      TypeValue = undefined     // Can contain the bad field
}

// Represents file not found error.
struct FileNotFoundError
{
    using base: Swag.BaseError     // Embedded base state.
    fileName:   #null string       // File name associated with this value.
}

// Represents invalid file name error.
struct InvalidFileNameError
{
    using base: Swag.BaseError     // Embedded base state.
    fileName:   #null string       // File name associated with this value.
}

// Represents an operation refused because it would leave the sandbox.
struct SandboxError
{
    using base: Swag.BaseError     // Embedded base state.
    path:       #null string       // Path the refused operation targeted.
}

// Represents invalid version.
struct InvalidVersion
{
    wantedVersion: u32     // Wanted version associated with this value.
    foundVersion:  u32     // Found version associated with this value.
}

// Make a string persistent for errors.
// That kind of string can be stored in an error struct.
func mkString(str: #null string)->#null string
{
    if str == null do
        return null

    let count = @countof(str)
    let ptr   = @getcontext().errorAllocator.alloc(count)
    @memcpy(ptr, @dataof(str), count)
    let safePtr = cast(#null [*] u8) ptr
    if !safePtr do
        return null
    return @mkstring(safePtr, count)
}
