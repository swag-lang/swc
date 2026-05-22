#global fileprivate
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

const StrictHandleFallback = cast(OrelseStrictHandle) 0x1234'u64
const StrictHandleResolved = cast(OrelseStrictHandle) null orelse StrictHandleFallback
#assert(#typeof(StrictHandleResolved) == OrelseStrictHandle)
#assert(StrictHandleResolved == StrictHandleFallback)

const NullableTypeInfo: #null typeinfo = null
const TypeInfoFallback: typeinfo = s32
const TypeInfoResolved = NullableTypeInfo orelse TypeInfoFallback
#assert(#typeof(TypeInfoResolved) == typeinfo)
#assert(TypeInfoResolved == s32)

const BoolResolved = false orelse true
#assert(#typeof(BoolResolved) == bool)
#assert(BoolResolved)

const AnyNullValue: any = null
#assert(AnyNullValue == null)

const AnyTrueValue: any = true
#assert(AnyTrueValue != null)
#assert(cast(bool) AnyTrueValue)

const AnyFalseValue: any = false
#assert(AnyFalseValue != null)
#assert(!cast(bool) AnyFalseValue)

func semaTest001()
{
    var raw: [2] u8 = ['x''u8, 'y''u8]
    let primary: const [..] u8 = null
    let resolved = primary orelse raw
    #assert(#typeof(resolved) == const [..] u8)
    @assert(@countof(resolved) == 2)
}

func semaTest002()
{
    var cstrData: [3] u8 = ['o''u8, 'k''u8, 0]
    let resolved = cast(cstring) null orelse cast(cstring) &cstrData[0]
    #assert(#typeof(resolved) == cstring)
    @assert(@countof(resolved) == 2)
}

func semaTest003()
{
    var probe = OrelseProbe{value: 7}
    var primary: IOrelseProbe = null
    let fallback = @mkinterface(&probe, #typeof(probe), IOrelseProbe)
    let resolved = primary orelse fallback
    #assert(#typeof(resolved) == IOrelseProbe)
    @assert(resolved.id() == 7)
}

func semaTest005(value: u8)->u8
{
    let resolved = value orelse 0
    #assert(#typeof(resolved) == u8)
    return resolved
}

func semaTest006(value: u8)->u8
{
    return 0 orelse value
}
