#global private

// Nullable VALUES are enforced at the use site: dereferencing, indexing, member
// access and calls through a still-nullable value are compile-time errors. Three
// sanctioned routes discharge the proof:
// - a dominating null test (flow narrowing);
// - an explicit 'notnull' assertion (runtime-checked in safety builds);
// - a '?.' guarded access, optionally closed by an 'orelse' fallback.
// The TYPE boundary is unchanged: a '#null T' never converts implicitly to 'T'.

struct NullableUsageItem
{
    value: s32
}

interface INullableUsage
{
    mtd get()->s32;
}

var g_nullableUsageStorage: s32

// Narrowing: the null test dominates the dereference.
func nullableUsageLocalDeref(use: bool)->s32
{
    var p: #null *s32
    if use do
        p = &g_nullableUsageStorage
    if p == null do
        return 0
    return dref p
}

func nullableUsageLocalIndex(count: u64)->s32
{
    var block: #null [*] s32
    if count do
        block = cast(#null [*] s32) &g_nullableUsageStorage
    if block == null do
        return 0
    return block[0]
}

// Crossing the type boundary requires the same control-flow proof...
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

// ...or a '?.' guarded access.
func nullableUsageOptional(value: #null *NullableUsageItem)->s32
{
    return value?.value orelse 0
}
