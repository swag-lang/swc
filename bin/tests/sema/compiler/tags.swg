#global fileprivate

#[Swag.ConstExpr]
func endianTag()->string
{
    return "Swag.Endian"
}

const EndianTagName = endianTag()

#assert(#hastag("Swag.Endian"))
#assert(#hastag(EndianTagName))
#assert(!#hastag("Swag.DoesNotExist"))

const EndianValue = #gettag("Swag.Endian", string, "big")
#assert(#typeof(EndianValue) == string)
#assert(EndianValue == "little")

const MissingBool = #gettag("Swag.Missing.Bool", bool, false)
#assert(#typeof(MissingBool) == bool)
#assert(!MissingBool)

const MissingByte = #gettag("Swag.Missing.Byte", u8, 42)
#assert(#typeof(MissingByte) == u8)
#assert(MissingByte == 42)

const MissingString = #gettag("Swag.Missing.String", string, "fallback")
#assert(#typeof(MissingString) == string)
#assert(MissingString == "fallback")

#test
{
    const LocalEndian = #gettag("Swag.Endian", string, "big")
    @assert(LocalEndian == "little")
}
