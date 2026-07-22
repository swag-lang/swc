#global private

// Nullable VALUES are used C-style: dereferencing, indexing, member access and
// calls do not require a narrowing proof at the use site. Proven null reads are
// reported by the static sanitizer and the runtime null-safety guards cover the
// rest in checked builds. Two limits frame that freedom:
// - the TYPE boundary: a '#null T' never converts implicitly to 'T';
// - the PARAMETER contract: a '#null' parameter whose first use on every path
//   requires its address is a compile-time error (see nullable_param_contract.swg).

struct NullableUsageItem
{
    value: s32
}

interface INullableUsage
{
    mtd get()->s32;
}

var g_nullableUsageStorage: s32

// C-like operations through nullable LOCALS.
func nullableUsageLocalDeref()->s32
{
    var p: #null *s32 = &g_nullableUsageStorage
    return dref p
}

func nullableUsageLocalIndex(count: u64)->s32
{
    var block: #null [*] s32
    if count do
        block = cast(#null [*] s32) &g_nullableUsageStorage
    return block[0]
}

// A '#null' parameter used conditionally keeps its contract alive.
func nullableUsageConditional(value: #null *NullableUsageItem, use: bool)->s32
{
    if use do
        return value.value
    return 0
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
