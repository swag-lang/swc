#global private

interface ILegacyPattern {}
struct LegacyPattern {}
impl ILegacyPattern for LegacyPattern {}

func oldIf(value: ILegacyPattern)
{
    if let item = cast #try (*LegacyPattern) value {}     // swc-expected-error {{sema_err_dynamic_cast_binding}}
}

func oldCase(value: ILegacyPattern)
{
    switch
    {
    case let item = cast #try (*LegacyPattern) value: break     // swc-expected-error {{sema_err_dynamic_cast_binding}}
    }
}

func oldPositive(value: ILegacyPattern)->bool
{
    return cast #try (*LegacyPattern) value != null     // swc-expected-error {{sema_err_dynamic_cast_test}}
}

func oldNegative(value: ILegacyPattern)->bool
{
    return null == (cast #try (*LegacyPattern) value)     // swc-expected-error {{sema_err_dynamic_cast_test}}
}

func oldCondition(value: ILegacyPattern)
{
    if (cast #try (*LegacyPattern) value) {}     // swc-expected-error {{sema_err_dynamic_cast_test}}
}

func oldBooleanCast(value: ILegacyPattern)->bool
{
    return cast(bool) (cast #try (*LegacyPattern) value)     // swc-expected-error {{sema_err_dynamic_cast_test}}
}

#assert(cast #try (ILegacyPattern) LegacyPattern != null)     // swc-expected-error {{sema_err_dynamic_cast_test}}
