#global fileprivate // 

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
    let value = 12'u32 orelse fallbackU32()
    @assert(value == 12'u32)
    @assert(GNullShortCounter == 0)
}

#test
{
    GNullShortCounter = 0
    var ptr: *s32 = null
    let value = ptr orelse fallbackPointer()
    @assert(value == &GNullShortValue)
    @assert(dref value == 33)
    @assert(GNullShortCounter == 1)
}

#test
{
    GNullShortCounter = 0
    let value: string = "ok"
    let resolved = value orelse fallbackString()
    @assert(resolved == "ok")
    @assert(GNullShortCounter == 0)
}

#test
{
    GNullShortCounter = 0
    var value: string = null
    let resolved = value orelse fallbackString()
    @assert(resolved == "fallback")
    @assert(GNullShortCounter == 1)
}
