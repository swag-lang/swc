#global private

// A slice and a string answer a condition with their data pointer, never with their count, so an
// empty one still answers true. A type that cannot hold null makes that test a constant, while
// the spelling reads like a test of emptiness, so every boolean context rejects it. A '#null'
// slice or string keeps all of those spellings: there the test asks a real question.

func boolTestEmptinessNullableString(text: #null string)->s32
{
    if text do
        return cast(s32) @countof(text!)
    return 0
}

func boolTestEmptinessNullableSlice(values: #null const [..] s32)->s32
{
    while values
    {
        return values![0]
    }

    return 0
}

// A count answers emptiness, which is what the rejected spelling reads like.
func boolTestEmptinessCount(text: string)->s32
{
    if @countof(text) do
        return 1
    return 0
}

// -----------------------------------------------------------------------------
// Rejected patterns.
// -----------------------------------------------------------------------------

func boolTestEmptinessErrString(text: string)->s32
{
    if text do     // swc-expected-error {{sema_err_bool_test_not_nullable_emptiness}}
        return 1
    return 0
}

func boolTestEmptinessErrSlice(values: const [..] s32)->s32
{
    if values do     // swc-expected-error {{sema_err_bool_test_not_nullable_emptiness}}
        return 1
    return 0
}

func boolTestEmptinessErrNot(text: string)->s32
{
    if !text do     // swc-expected-error {{sema_err_bool_test_not_nullable_emptiness}}
        return 0
    return 1
}

func boolTestEmptinessErrLogical(values: const [..] s32)->bool
{
    return values and values[0] != 0     // swc-expected-error {{sema_err_bool_test_not_nullable_emptiness}}
}

func boolTestEmptinessErrTernary(text: string)->s32
{
    return text ? 1 : 0     // swc-expected-error {{sema_err_bool_test_not_nullable_emptiness}}
}

func boolTestEmptinessErrExplicitCast(text: string)->bool
{
    return cast(bool) text     // swc-expected-error {{sema_err_bool_test_not_nullable_emptiness}}
}