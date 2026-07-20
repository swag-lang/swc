#global private
using Swag

#[Swag.Strict]
alias OrelseStrictHandle = #null const *void

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

func zeroLiteralOrelseReturn(value: u8)->u8
{
    return 0 orelse value
}

func strictHandleFallback()->bool
{
    var storage: s32 = 1
    let fallback = cast(OrelseStrictHandle) &storage
    let resolved = cast(OrelseStrictHandle) null orelse fallback
    #assert(#typeof(resolved) == OrelseStrictHandle)
    return resolved == fallback and resolved != null
}

func typeInfoFallback()->bool
{
    let primary: #null typeinfo = null
    let fallback: typeinfo = s32
    let resolved = primary orelse fallback
    return resolved == s32
}

func cstringFallback()->bool
{
    var data: [3] u8 = ['o''u8, 'k''u8, 0]
    let resolved = cast(#null cstring) null orelse cast(cstring) &data[0]
    #assert(#typeof(resolved) == cstring)
    return resolved != null and @countof(resolved) == 2
}

func interfaceFallback()->bool
{
    var probe = OrelseProbe{value: 55}
    var primary: IOrelseProbe = null
    let fallback = @mkinterface(&probe, #typeof(probe), IOrelseProbe)
    let resolved = primary orelse fallback
    return resolved.id() == 55
}

#test
{
    @assert(zeroLiteralOrelseReturn(9'u8) == 9'u8)
}

#test
{
    @assert(strictHandleFallback())
}

#test
{
    @assert(typeInfoFallback())
}

#test
{
    @assert(cstringFallback())
    @assert(interfaceFallback())
}

#test
{
    func explicitAnyChecks()->bool
    {
        let missing: #null any = null
        let boolTrue: any = true
        let boolFalse: any = false
        return missing == null and
               boolTrue != null and
               boolFalse != null and
               cast(bool) boolTrue and
               !cast(bool) boolFalse
    }

    @assert(explicitAnyChecks())
}
