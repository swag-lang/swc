#global private
using Swag

#[Swag.Strict]
alias OrelseStrictHandle = const *void

interface IOrelseProbe
{
    mtd id()->u32;
}

struct OrelseProbe
{
    value: u32
}

impl IOrelseProbe for OrelseProbe
{
    mtd impl id()->u32 => .value
}

#test
{
    func zeroLiteralOrelseReturn(value: u8)->u8
    {
        return 0 orelse value
    }

    const V = #run zeroLiteralOrelseReturn(9'u8)
    #assert(#typeof(V) == u8)
    #assert(V == 9'u8)
}

#test
{
    func strictHandleFallback()->bool
    {
        var storage: s32 = 1
        let fallback = cast(OrelseStrictHandle) &storage
        let resolved = cast(OrelseStrictHandle) null orelse fallback
        #assert(#typeof(resolved) == OrelseStrictHandle)
        return resolved == fallback and resolved != null
    }

    const V = #run strictHandleFallback()
    #assert(V)
}

#test
{
    func typeInfoFallback()->bool
    {
        let primary: #null typeinfo = null
        let fallback: typeinfo = s32
        let resolved = primary orelse fallback
        return resolved == s32
    }

    const V = #run typeInfoFallback()
    #assert(V)
}

#test
{
    func cstringFallback()->bool
    {
        var data: [3] u8 = ['o''u8, 'k''u8, 0]
        let resolved = cast(cstring) null orelse cast(cstring) &data[0]
        return resolved != null and @countof(resolved) == 2
    }

    const V = #run cstringFallback()
    #assert(V)
}

#test
{
    func interfaceFallback()->bool
    {
        var probe = OrelseProbe{value: 55}
        var primary: IOrelseProbe = null
        let fallback = @mkinterface(&probe, #typeof(probe), IOrelseProbe)
        let resolved = primary orelse fallback
        return resolved.id() == 55
    }

    const V = #run interfaceFallback()
    #assert(V)
}

#test
{
    func explicitAnyChecks()->bool
    {
        let missing: any = null
        let boolTrue: any = true
        let boolFalse: any = false
        return missing == null and
               boolTrue != null and
               boolFalse != null and
               cast(bool) boolTrue and
               !cast(bool) boolFalse
    }

    const V = #run explicitAnyChecks()
    #assert(V)
}
