#global public
#global namespace Errors

// Reports input that does not follow the expected format.
struct InvalidFormatError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Reports input that uses a format or a feature this implementation does not support.
struct UnsupportedFormatError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Reports an argument outside what an operation accepts.
struct BadParameterError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Reports malformed text, with the position where parsing stopped when it is known.
struct SyntaxError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        line, col:  u64                // One-based line and column, or zero when unknown.
        seek:       u64                // Byte offset in the parsed text, when known.
    }
}

// Reports a value or a size beyond what can be represented or what a limit allows.
struct OverflowError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Reports text that ends before a complete value could be parsed.
struct ParseIncompleteError
{
    public using base: Swag.BaseError     // Embedded base state.
}

// Reports a value that cannot be serialized or deserialized.
struct SerializationError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        field:      TypeValue          // Field being processed, when the error concerns one.
    }
}

// Reports a file or directory that does not exist.
struct FileNotFoundError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        fileName:   string?            // Path that was not found, when known.
    }
}

// Reports a path that the operating system rejects as a file name.
struct InvalidFileNameError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        fileName:   string?            // Rejected path, when known.
    }
}

// Represents an operation refused because it would leave the sandbox.
struct SandboxError
{
    public
    {
        using base: Swag.BaseError     // Embedded base state.
        path:       string?            // Path the refused operation targeted.
    }
}

// Reports stored data whose version the reader does not support.
struct InvalidVersion
{
    public
    {
        wantedVersion: u32     // Version the reader supports.
        foundVersion:  u32     // Version found in the data.
    }
}

// Returns the text an error value carries, so a report can print what failed.
//
// `err` is the value a `catch` binds. The text is read from the [[Swag.BaseError]] a standard
// error embeds as its first field; an error type without one, or with an empty message,
// answers with its type name instead, so the result is always printable. A `null` error
// answers with an empty string.
func message(err: any?)->string
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
            let base = cast(const *Swag.BaseError) err.buffer
            let text = base.message orelse ""
            return text.count ? text : name
        }

        let structType = cast #assume(const *Swag.TypeInfoStruct) type
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

// Returns a copy of `str` that an error value can keep after the current scope ends.
//
// The copy lives in the context's error allocator, which is where a `fail` stores its error.
// A null `str` returns null.
func mkString(str: string?)->string?
{
    if str == null do
        return null
    if not str.count do
        return ""

    // A foreign thread can copy a message before its first 'fail' initializes error storage.
    let context = Swag.getContext()
    if not context.errorAllocator.capacity
    {
        const Capacity = #run Swag.compiler().getBuildCfg()!.errorAllocatorCapacity
        context.errorAllocator.setCapacity(Capacity, context.allocator!)
    }

    let count = str.count
    let ptr   = cast([*] u8?) context.errorAllocator.alloc(count)
    if not ptr do
        return null
    Swag.memcpy(ptr, str.buffer, count)
    return Swag.makeString(ptr, count)
}
