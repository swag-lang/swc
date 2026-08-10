#global namespace Serialization
#global namespace Write
#global public

using Swag

// Options for customizing JSON formatting.
struct JsonOptions
{
    public
    {
        indentLevel: u32 = 4     // Number of spaces per indentation level.
        saveBlanks:  bool        // Whether to include indentation and line breaks.
    }
}

// A JSON writer.
struct Json
{
    public options: JsonOptions     // Formatting options.

    internal
    {
        output:         *ConcatBuffer              = undefined        // Output buffer for generated JSON.
        indent:         u32                                           // Current indentation level.
        containerDepth: u32                                           // Current logical nesting depth for arrays/objects.
        fmtInt:         StrConv.ConvertFormatInt                      // Format used for converting integers.
        fmtFloat:       StrConv.ConvertFormatFloat = {fmt: 'g'u8}     // Format used for converting floating-point numbers.
        lastSeekValue:  ConcatBufferPosition                          // Position used for rollback of trailing commas.
    }
}

impl Json
{
    // Returns true indicating this writer produces textual output.
    mtd isTextual()->bool
    {
        return true
    }

    // Returns the identity written for a type value: the canonical runtime crc.
    mtd typeCrcOf(type: #null typeinfo)->u32
    {
        if !type do
            return 0
        return type.crc
    }

    internal mtd writeIndent()
    {
        if !.options.saveBlanks do
            return
        for .indent * .options.indentLevel do
            .output.addNative(' 'u8)
    }

    internal mtd writeString(value: #null string)
    {
        const Hex = "0123456789ABCDEF"

        .output.addNative('"'u8)
        for c in value
        {
            switch c
            {
            case '"':
                .output.addBytes("\\\"")

            case '\\':
                .output.addBytes("\\\\")

            case '\b':
                .output.addBytes("\\b")

            case '\f':
                .output.addBytes("\\f")

            case '\n':
                .output.addBytes("\\n")

            case '\r':
                .output.addBytes("\\r")

            case '\t':
                .output.addBytes("\\t")

            default:
                if c < 0x20
                {
                    .output.addBytes("\\u00")
                    .output.addNative(Hex[c >> 4])
                    .output.addNative(Hex[c & 0x0F])
                }
                else do
                    .output.addNative(c)
            }
        }

        .output.addNative('"'u8)
    }

    // Initializes the JSON writer with the given output buffer.
    mtd startWrite(buf: *ConcatBuffer)
    {
        .output         = buf
        .indent         = 0
        .containerDepth = 0
        .lastSeekValue  = {}
    }

    // Begins the root element (no-op for JSON).
    mtd beginRoot() {}

    // Ends the root element (no-op for JSON).
    mtd endRoot() {}

    // Begins a JSON array.
    mtd beginSequence(_typeElem: #null typeinfo, _data: #null const *void, _countElem: u64)->bool
    {
        .output.addBytes("[")
        .lastSeekValue  = .output.position()
        .containerDepth += 1
        if .options.saveBlanks
        {
            .output.addBytes("\n")
            .indent += 1
            .writeIndent()
        }

        return false
    }

    // Ends a JSON array.
    mtd endSequence()
    {
        .output.truncate(.lastSeekValue)
        if .options.saveBlanks
        {
            .output.addBytes("\n")
            .indent -= 1
            .writeIndent()
        }

        .containerDepth -= 1
        .output.addBytes("]")
        .lastSeekValue = .output.position()
    }

    // Begins a JSON object section.
    mtd beginSection(_kind: SectionKind)
    {
        .output.addBytes("{")
        .lastSeekValue  = .output.position()
        .containerDepth += 1
        if .options.saveBlanks
        {
            .output.addBytes("\n")
            .indent += 1
            .writeIndent()
        }
    }

    // Ends a JSON object section.
    mtd endSection()
    {
        .output.truncate(.lastSeekValue)
        if .options.saveBlanks
        {
            .output.addBytes("\n")
            .indent -= 1
            .writeIndent()
        }

        .containerDepth -= 1
        .output.addBytes("}")
        .lastSeekValue = .output.position()
    }

    // Begins writing a struct (treated as a JSON object).
    mtd beginStruct(_structType: #null typeinfo, _structData: #null const *u8)->bool
    {
        .beginSection(.Ordered)
        return false
    }

    // Ends writing a struct.
    mtd endStruct()
    {
        .endSection()
    }

    // Begins a named JSON element (a key-value pair).
    mtd beginElement(val: TypeValue)
    {
        .writeString(val.name)
        .output.addNative(':'u8)
        if .options.saveBlanks do
            .output.addBytes(" ")
    }

    // Ends a named JSON element (no-op).
    mtd endElement(val: TypeValue) {}

    // Begins a JSON value (no-op).
    mtd beginValue() {}

    // Ends a JSON value and appends a comma and optional newline.
    mtd endValue()
    {
        if .containerDepth == 0 do
            return

        .lastSeekValue = .output.position()
        .output.addBytes(",")
        if .options.saveBlanks do
            .output.addBytes("\n")
        .writeIndent()
    }

    /////////////////////////////////
    // VALUES
    /////////////////////////////////

    // Writes a native value (bool, float, int, string) as a JSON value.
    mtd(NT) writeNative(value: NT)
    {
        #static if NT == bool
        {
            .output.addBytes(value ? "true" : "false")
        }
        elif Reflection.isFloat(NT)
        {
            StrConv.convertFloat(.output, value, .fmtFloat)
        }
        elif Reflection.isInteger(NT)
        {
            StrConv.convertInt(.output, value, .fmtInt)
        }
        elif Reflection.isString(NT)
        {
            .writeString(value)
        }
        else
        {
            #error("invalid type")
        }
    }
}
