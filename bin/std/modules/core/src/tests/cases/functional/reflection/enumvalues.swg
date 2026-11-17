#global if #command == Swag.CompilerCommand.Test
#global private

enum ByteValue: u8
{
    Missing = 0
    Present = 1
}

enum WordValue: u16
{
    Present = 42
}

#[Swag.EnumFlags]
enum WideFlags: u64
{
    None  = 0
    Read  = 1
    Write = 0x1_0000_0000'u64
    Both  = Read | Write
}

#test
{
    var present = ByteValue.Present
    var missing: u8 = 7
    Swag.require(Reflection.enumUnderlyingType(#typeof(ByteValue)) == u8)
    Swag.require(Reflection.enumUnderlyingType(s32) == s32)
    Swag.require(Reflection.hasDeclaredValue(#typeof(ByteValue), &present))
    Swag.require(not Reflection.hasDeclaredValue(#typeof(ByteValue), &missing))
    Swag.require(not Reflection.hasDeclaredValue(null, &present))
    Swag.require(not Reflection.hasDeclaredValue(#typeof(ByteValue), null))
    Swag.require(Reflection.enumName(#typeof(ByteValue), &present) == "ByteValue.Present")
    Swag.require(Reflection.enumName(#typeof(ByteValue), null).isEmpty())
    Swag.require(Reflection.enumName(s32, &present).isEmpty())
    Swag.require(Reflection.enumValue(#typeof(ByteValue), "Absent") == null)
    Swag.require(Reflection.enumValue(s32, "Present") == null)
    Swag.require(Reflection.enumValue(null, "Present") == null)
}

#test
{
    var present = WordValue.Present
    Swag.require(Reflection.hasDeclaredValue(#typeof(WordValue), &present))
    Swag.require(Reflection.enumName(#typeof(WordValue), &present, fullyQualified: false) == "Present")
}

#test
{
    var none        = WideFlags.None
    var both        = WideFlags.Both
    var unknown: u64 = 0x2_0000_0000'u64
    var partlyKnown: u64 = 0x2_0000_0001'u64

    Swag.require(Reflection.hasDeclaredValue(#typeof(WideFlags), &both))
    Swag.require(not Reflection.hasDeclaredValue(#typeof(WideFlags), &partlyKnown))
    Swag.require(Reflection.enumName(#typeof(WideFlags), &none) == "WideFlags.None")
    Swag.require(Reflection.enumName(#typeof(WideFlags), &both) == "WideFlags.Read | WideFlags.Write")
    Swag.require(Reflection.enumName(#typeof(WideFlags), &partlyKnown, fullyQualified: false) == "Read")
    Swag.require(Reflection.enumName(#typeof(WideFlags), &unknown).isEmpty())
}
