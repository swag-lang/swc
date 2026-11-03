#global private

var GNullShortCounter: s32
var GNullShortValue:   s32 = 33

func fallbackU32()->u32
{
    GNullShortCounter += 1
    return 91'u32
}

func fallbackPointer()->*s32
{
    GNullShortCounter += 1
    return &GNullShortValue
}

func fallbackString()->string
{
    GNullShortCounter += 1
    return "fallback"
}

#test
{
    GNullShortCounter = 0
    let value = 12'u32 != 0 ? 12'u32 : fallbackU32()
    Swag.require(value == 12'u32)
    Swag.require(GNullShortCounter == 0)
}

#test
{
    GNullShortCounter = 0
    var ptr: *s32? = null
    let value      = ptr orelse fallbackPointer()
    Swag.require(value == &GNullShortValue)
    Swag.require(value[] == 33)
    Swag.require(GNullShortCounter == 1)
}

#test
{
    GNullShortCounter = 0
    let value: string = "ok"
    let resolved      = value orelse fallbackString()
    Swag.require(resolved == "ok")
    Swag.require(GNullShortCounter == 0)
}

#test
{
    GNullShortCounter = 0
    var value: string? = null
    let resolved       = value orelse fallbackString()
    Swag.require(resolved == "fallback")
    Swag.require(GNullShortCounter == 1)
}
