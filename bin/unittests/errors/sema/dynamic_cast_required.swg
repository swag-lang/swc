#global private

interface RequiredCastView { mtd value()->s32 }
struct RequiredCastValue { number: s32 }
impl RequiredCastView for RequiredCastValue
{
    mtd value()->s32 => .number
}

#test
{
    var value: any = 42's32
    let result     = cast(s32) value     // swc-expected-error {{sema_err_dynamic_cast_modifier}}
}

#test
{
    var value: RequiredCastValue
    let view   = cast(RequiredCastView) &value
    let result = cast(*RequiredCastValue) view     // swc-expected-error {{sema_err_dynamic_cast_modifier}}
}
