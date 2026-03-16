#global fileprivate // swc-option suite-jit

var GNullCoercCounter: s32
var GNullCoercValue:   s32 = 33

func fallbackU32()->u32
{
    GNullCoercCounter += 1
    return 91'u32
}

func fallbackPointer()->*s32
{
    GNullCoercCounter += 1
    return &GNullCoercValue
}

func fallbackString()->string
{
    GNullCoercCounter += 1
    return "fallback"
}

#test
{
    func intSkipsFallback()->s32
    {
        GNullCoercCounter = 0
        let value = 12'u32 orelse fallbackU32()
        return cast(s32) value + GNullCoercCounter * 100
    }

    const V = #run intSkipsFallback()
    #assert(V == 12)
}

#test
{
    func pointerUsesFallbackOnce()->s32
    {
        GNullCoercCounter = 0
        var ptr: *s32 = null
        let value = ptr orelse fallbackPointer()
        return dref value + GNullCoercCounter * 100
    }

    const V = #run pointerUsesFallbackOnce()
    #assert(V == 133)
}

#test
{
    func stringSkipsFallback()->bool
    {
        GNullCoercCounter = 0
        let value: string = "ok"
        let resolved = value orelse fallbackString()
        return resolved == "ok" and GNullCoercCounter == 0
    }

    const V = #run stringSkipsFallback()
    #assert(V)
}

#test
{
    func nullStringUsesFallbackOnce()->bool
    {
        GNullCoercCounter = 0
        var value: string = null
        let resolved = value orelse fallbackString()
        return resolved == "fallback" and GNullCoercCounter == 1
    }

    const V = #run nullStringUsesFallbackOnce()
    #assert(V)
}
