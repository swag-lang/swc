#global private

enum RuntimeEnumCastColour
{
    Red
    Green
}

enum RuntimeEnumCastRatio: f32
{
    Normal = 1.0
    Fast   = 2.0
}

const invalidRuntimeEnumCast: RuntimeEnumCastColour = cast(RuntimeEnumCastColour, 99's32) // swc-expected-error {{sema_err_cannot_cast}}
const validFloatEnumCast: RuntimeEnumCastRatio = cast(RuntimeEnumCastRatio, 2.0'f32)

func runtimeEnumCast(raw: s32)->RuntimeEnumCastColour
{
    return cast(RuntimeEnumCastColour, raw)     // swc-expected-error {{sema_err_cannot_cast}}
}

func runtimeEnumTryCast(raw: s32)->RuntimeEnumCastColour fail
{
    return try cast(RuntimeEnumCastColour, raw)     // swc-expected-error {{sema_err_cannot_cast}}
}

func runtimeFloatEnumCast(raw: f32)->RuntimeEnumCastRatio
{
    return cast(RuntimeEnumCastRatio, raw)     // swc-expected-error {{sema_err_cannot_cast}}
}

#[Swag.EnumFlags]
enum RuntimeEnumCastFlags: u32
{
    Read
    Write
}

func runtimeFlagsCast(raw: u32)->RuntimeEnumCastFlags
{
    return cast(RuntimeEnumCastFlags, raw)
}

#[Swag.Incomplete]
enum RuntimeOpenEnum: u32
{
    Known = 1
}

func runtimeOpenEnumCast(raw: u32)->RuntimeOpenEnum
{
    return cast(RuntimeOpenEnum, raw)
}

#test
{
    var raw: u32 = 99
    Swag.require(cast(u32, runtimeOpenEnumCast(raw)) == 99)
}
