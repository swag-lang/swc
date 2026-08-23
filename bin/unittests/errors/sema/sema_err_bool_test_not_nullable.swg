#global private

// A single-value pointer answers a condition by testing itself against null. A pointer type
// that cannot hold null makes that test a constant, while the spelling reads like a test of
// the pointed value, so every boolean context rejects it. A '#null' pointer keeps all of
// those spellings: there the test asks a real question.

struct NonNullConditionItem
{
    value: s32
}

func nonNullConditionNullableIf(item: #null *NonNullConditionItem)->s32
{
    if item do
        return item.value
    return 0
}

func nonNullConditionNullableNot(item: #null *NonNullConditionItem)->s32
{
    if !item do
        return 0
    return item.value
}

func nonNullConditionNullableWhile(scan: #null *NonNullConditionItem)->s32
{
    while scan
    {
        return scan.value
    }

    return 0
}

// Flow narrowing does not turn the question into a contradiction: the declared type still
// carries it, so a proven pointer keeps every spelling, exactly as 'orelse' keeps a dead
// fallback on a nullable-declared value.
func nonNullConditionNarrowed(item: #null *NonNullConditionItem)->s32
{
    if item == null do
        return 0
    if item do
        return item.value
    return 0
}

// A non-null pointer offers the pointed value instead.
func nonNullConditionPointee(flag: *bool)->s32
{
    if flag[] do
        return 1
    return 0
}

// -----------------------------------------------------------------------------
// Rejected patterns.
// -----------------------------------------------------------------------------

func nonNullConditionErrIf(item: *NonNullConditionItem)->s32
{
    if item do     // swc-expected-error {{sema_err_bool_test_not_nullable}}
        return item.value
    return 0
}

func nonNullConditionErrWhile(item: *NonNullConditionItem)->s32
{
    while item     // swc-expected-error {{sema_err_bool_test_not_nullable}}
    {
        return item.value
    }

    return 0
}

func nonNullConditionErrNot(item: *NonNullConditionItem)->s32
{
    if !item do     // swc-expected-error {{sema_err_bool_test_not_nullable}}
        return 0
    return item.value
}

func nonNullConditionErrLogical(item: *NonNullConditionItem)->bool
{
    return item and item.value != 0     // swc-expected-error {{sema_err_bool_test_not_nullable}}
}

func nonNullConditionErrTernary(item: *NonNullConditionItem)->s32
{
    return item ? item.value : 0     // swc-expected-error {{sema_err_bool_test_not_nullable}}
}

func nonNullConditionErrExplicitCast(item: *NonNullConditionItem)->bool
{
    return cast(bool) item     // swc-expected-error {{sema_err_bool_test_not_nullable}}
}

func nonNullConditionErrAssert(item: *NonNullConditionItem)
{
    @assert(item)     // swc-expected-error {{sema_err_bool_test_not_nullable}}
}

impl NonNullConditionItem
{
    mtd errMe()->s32
    {
        if me do     // swc-expected-error {{sema_err_bool_test_not_nullable}}
            return .value
        return 0
    }
}
