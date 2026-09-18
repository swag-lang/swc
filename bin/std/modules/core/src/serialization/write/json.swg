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

// Writes declaration-driven JSON.
//
// Non-finite floating-point values have no JSON representation and are written as
// `null`. Strings escape every JSON control character and preserve valid UTF-8.
struct Json
{
    public options: JsonOptions     // Formatting options.

    internal
    {
        late output:    *ConcatBuffer                                 // Output buffer for generated JSON.
        indent:         u32                                           // Current indentation level.
        containerDepth: u32                                           // Current logical nesting depth for arrays/objects.
        fmtInt:         StrConv.ConvertFormatInt                      // Format used for converting integers.
        fmtFloat:       StrConv.ConvertFormatFloat = {fmt: 'g'u8}     // Format used for converting floating-point numbers.
        lastSeekValue:  ConcatBufferPosition                          // Position used for rollback of trailing commas.
    }
}

impl Json
{
    // Returns true, because JSON is a textual format.
    mtd isTextual()->bool => true

    // Returns the identity written for a type value: the canonical runtime crc.
    mtd typeCrcOf(type: typeinfo?)->u32
    {
        if not type do
            return 0
        return type.crc
    }

    internal mtd writeIndent()
    {
        if not .options.saveBlanks do
            return
        for .indent * .options.indentLevel do
            .output.addNative(' 'u8)
    }

    internal mtd writeString(value: string?)
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

    // Starts writing a document to `buf`.
    mtd startWrite(buf: *ConcatBuffer)
    {
        .output         = buf
        .indent         = 0
        .containerDepth = 0
        .lastSeekValue  = {}
    }

    // Does nothing: a JSON document needs no root mark.
    mtd beginRoot() {}

    // Does nothing: a JSON document needs no root mark.
    mtd endRoot() {}

    // Begins a JSON array.
    mtd beginSequence(_typeElem: typeinfo?, _data: const *void?, _countElem: u64)->bool
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

    // Opens a struct as a JSON object and returns false, so the encoder writes its fields.
    mtd beginStruct(_structType: typeinfo?, _structData: const *u8?)->bool
    {
        .beginSection(.Ordered)
        return false
    }

    // Closes the JSON object of the current struct.
    mtd endStruct()
    {
        .endSection()
    }

    // Writes the key of the property `val`.
    mtd beginElement(val: TypeValue)
    {
        .writeString(wireFieldKey(val))
        .output.addNative(':'u8)
        if .options.saveBlanks do
            .output.addBytes(" ")
    }

    // Does nothing: a property ends with its value.
    mtd endElement(val: TypeValue) {}

    // Does nothing: a JSON value needs no opening mark.
    mtd beginValue() {}

    // Appends the separator that follows a value inside an array or an object.
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

    // Writes a Boolean, a number, or a string as a JSON value.
    mtd(NT) writeNative(value: NT)
    {
        #static if NT == bool
        {
            .output.addBytes(value ? "true" : "false")
        }
        elif Reflection.isFloat(NT)
        {
            if Math.isFinite(value) do
                StrConv.convertFloat(.output, value, .fmtFloat)
            else do
                .output.addBytes("null")
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
