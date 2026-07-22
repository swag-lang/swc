#global private

struct NullableUsageItem
{
    value: s32
}

interface INullableUsage
{
    mtd get()->s32;
}

func nullableUsageDerefReject(value: #null *s32)
{
    let result = dref value // swc-expected-error {{sema_err_nullable_value_requires_non_null}}
}

func nullableUsageMemberReject(value: #null *NullableUsageItem)
{
    let result = value.value // swc-expected-error {{sema_err_nullable_value_requires_non_null}}
}

func nullableUsageInterfaceReject(value: #null INullableUsage)
{
    let result = value.get() // swc-expected-error {{sema_err_nullable_value_requires_non_null}}
}

func nullableUsageBlockIndexReject(value: #null [*] s32)
{
    let result = value[0] // swc-expected-error {{sema_err_nullable_value_requires_non_null}}
}

func nullableUsageSliceIndexReject(value: #null [..] s32)
{
    let result = value[0] // swc-expected-error {{sema_err_nullable_value_requires_non_null}}
}

func nullableUsageStringIndexReject(value: #null string)
{
    let result = value[0] // swc-expected-error {{sema_err_nullable_value_requires_non_null}}
}

func nullableUsageCallReject(value: #null func()->s32)
{
    let result = value() // swc-expected-error {{sema_err_nullable_value_requires_non_null}}
}

func nullableUsageRefined(value: #null *NullableUsageItem, block: #null [*] s32, callback: #null func()->s32)->s32
{
    if value == null or block == null or callback == null do
        return 0

    return value.value + block[0] + callback()
}

func nullableUsageAsserted(value: #null *NullableUsageItem)->s32
{
    return (notnull value).value
}
