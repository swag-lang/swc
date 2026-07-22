#global private

// Nullable values are used C-style: dereferencing, indexing, member access and
// calls do NOT require a narrowing proof at the use site. Proven null dereferences
// are reported by the static sanitizer, and the runtime null-safety guards cover
// the rest in checked builds. Nullability is enforced at the TYPE boundary only:
// a '#null T' never converts implicitly to 'T' (see narrowing and 'notnull').

struct NullableUsageItem
{
    value: s32
}

interface INullableUsage
{
    mtd get()->s32;
}

func nullableUsageDeref(value: #null *s32)->s32
{
    return dref value
}

func nullableUsageMember(value: #null *NullableUsageItem)->s32
{
    return value.value
}

func nullableUsageInterface(value: #null INullableUsage)->s32
{
    return value.get()
}

func nullableUsageBlockIndex(value: #null [*] s32)->s32
{
    return value[0]
}

func nullableUsageSliceIndex(value: #null [..] s32)->s32
{
    return value[0]
}

func nullableUsageStringIndex(value: #null string)->u8
{
    return value[0]
}

func nullableUsageCall(value: #null func()->s32)->s32
{
    return value()
}

// Crossing the type boundary requires a control-flow proof...
func nullableUsageRefined(value: #null *NullableUsageItem, block: #null [*] s32, callback: #null func()->s32)->s32
{
    if value == null or block == null or callback == null do
        return 0

    return value.value + block[0] + callback()
}

// ...or an explicit 'notnull' assertion.
func nullableUsageAsserted(value: #null *NullableUsageItem)->s32
{
    return (notnull value).value
}
