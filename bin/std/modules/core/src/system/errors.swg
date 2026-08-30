#global public
#global namespace Errors

// Represents invalid format error.
struct InvalidFormatError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Represents unsupported format error.
struct UnsupportedFormatError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Represents bad parameter error.
struct BadParameterError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Represents syntax error.
struct SyntaxError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        line, col:  u64                // Line associated with this value.
        seek:       u64                // Seek associated with this value.
    }
}

// Represents overflow error.
struct OverflowError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Represents parse incomplete error.
struct ParseIncompleteError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Represents serialization error.
struct SerializationError
{
    public
    {
        using base: Swag.BaseError            // Embedded base state.
        field:      TypeValue = undefined     // Can contain the bad field
    }
}

// Represents file not found error.
struct FileNotFoundError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        fileName:   #null string       // File name associated with this value.
    }
}

// Represents invalid file name error.
struct InvalidFileNameError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        fileName:   #null string       // File name associated with this value.
    }
}

// Represents an operation refused because it would leave the sandbox.
struct SandboxError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        path:       #null string       // Path the refused operation targeted.
    }
}

// Represents invalid version.
struct InvalidVersion
{
    public
    {
        wantedVersion: u32     // Wanted version associated with this value.
        foundVersion:  u32     // Found version associated with this value.
    }
}

// Returns the text an error value carries, so a report can print what failed.
//
// `err` is the value a `catch` binds. The text is read from the [[Swag.BaseError]] a standard
// error embeds as its first field; an error type without one, or with an empty message,
// answers with its type name instead, so the result is always printable. A `null` error
// answers with an empty string.
func message(err: #null any)->string
{
    if err == null do
        return ""

    var type = Reflection.resolveAliases(Swag.kindOf(err))
    let name = type.name orelse ""

    // Walk the leading embedded structs: the base of an error family sits at offset zero,
    // however deep the derivation goes.
    while Reflection.isStruct(type)
    {
        if type == Swag.BaseError
        {
            let base = cast(const *Swag.BaseError) err.buffer!
            let text = base.message orelse ""
            return text.count ? text : name
        }

        let structType = cast(const *Swag.TypeInfoStruct) type
        let fields     = structType.fields
        if fields.count == 0 or fields![0].offset != 0 do
            break

        let fieldType = fields![0].pointedType
        if fieldType == null do
            break

        type = fieldType
    }

    return name
}

// Make a string persistent for errors.
// That kind of string can be stored in an error struct.
func mkString(str: #null string)->#null string
{
    if str == null do
        return null

    let count = str.count
    let ptr   = Swag.getContext().errorAllocator.alloc(count)
    Swag.memcpy(ptr, str.buffer, count)
    let safePtr = cast(#null [*] u8) ptr
    if !safePtr do
        return null
    return Swag.makeString(safePtr, count)
}
