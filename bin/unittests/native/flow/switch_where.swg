#global private

// A `where` guard refines a case that already matched: the case value is tested first, and the
// guard runs only when that test succeeds. Every guard here counts its evaluations, so a guard
// run for a value its case never matches is visible.

enum SwitchWhereTag
{
    A
    B
    C
}

func countedGuard(calls: *s32, result: bool)->bool
{
    calls[] += 1
    return result
}

#test
{
    var calls = 0
    var hits  = 0
    for index in 100
    {
        let tag = index % 2 == 0 ? SwitchWhereTag.A : SwitchWhereTag.B
        switch tag
        {
        case .C where countedGuard(&calls, true): hits += 1
        }
    }

    Swag.require(calls == 0)
    Swag.require(hits == 0)
}

func guardedValue(value: s32, calls: *s32)->s32
{
    switch value
    {
    case 1, 2 where countedGuard(calls, false):           return 1
    case 1, 2 where countedGuard(calls, true):            return 2
    case 10 to 20 where countedGuard(calls, true):        return 3
    case 30 until 40, 50 where countedGuard(calls, true): return 4
    default: return 0
    }
}

#test
{
    var calls = 0
    Swag.require(guardedValue(3, &calls) == 0)
    Swag.require(calls == 0)

    Swag.require(guardedValue(2, &calls) == 2)
    Swag.require(calls == 2)

    calls = 0
    Swag.require(guardedValue(15, &calls) == 3)
    Swag.require(calls == 1)

    calls = 0
    Swag.require(guardedValue(25, &calls) == 0)
    Swag.require(calls == 0)

    // A range that fails still leaves the values listed after it to test.
    Swag.require(guardedValue(50, &calls) == 4)
    Swag.require(calls == 1)
}

func guardedName(value: string, calls: *s32)->s32
{
    switch value
    {
    case "keep" where countedGuard(calls, true): return 1
    case "drop": return 2
    default:     return 0
    }
}

#test
{
    var calls = 0
    Swag.require(guardedName("drop", &calls) == 2)
    Swag.require(guardedName("other", &calls) == 0)
    Swag.require(calls == 0)

    Swag.require(guardedName("keep", &calls) == 1)
    Swag.require(calls == 1)
}

// The guard is a call the compiler inlines, and it still waits for the type test.
func guardedType(value: const any, calls: *s32)->s32
{
    switch value
    {
    case s32 as number where countedGuard(calls, number[] > 0): return 1
    case string where countedGuard(calls, true): return 2
    default: return 0
    }
}

#test
{
    var calls = 0
    Swag.require(guardedType(true, &calls) == 0)
    Swag.require(calls == 0)

    Swag.require(guardedType("text", &calls) == 2)
    Swag.require(calls == 1)

    calls = 0
    Swag.require(guardedType(-4's32, &calls) == 0)
    Swag.require(calls == 1)
}

#test
{
    var calls = 0
    var hits  = 0
    for index in 10
    {
        switch
        {
        case index == 7 where countedGuard(&calls, true): hits += 1
        }
    }

    Swag.require(calls == 1)
    Swag.require(hits == 1)
}

func findName(value: *string?)->*string? => value

#test
{
    var calls = 0
    var name  = "value"
    var hits  = 0
    for index in 4
    {
        let candidate = index == 2 ? &name : null
        switch
        {
        case let found = findName(candidate) where countedGuard(&calls, found[] == "value"): hits += 1
        }
    }

    Swag.require(calls == 1)
    Swag.require(hits == 1)
}

// `fallthrough` enters the next value case's body without testing it, so its guard does not run.
#test
{
    var calls = 0
    var hits  = 0
    var value = 1
    switch value
    {
    case 1:
        hits += 1
        fallthrough

    case 2 where countedGuard(&calls, false):
        hits += 10
    }

    Swag.require(calls == 0)
    Swag.require(hits == 11)
}

// `fallthrough` into a typed case tests the type first, and runs the guard only on a match.
func fallthroughIntoType(value: const any, calls: *s32)->s32
{
    var result = 0
    switch value
    {
    case bool:
        result += 1
        fallthrough

    case s32 where countedGuard(calls, true):
        result += 10

    default:
        result += 100
    }

    return result
}

#test
{
    var calls = 0
    Swag.require(fallthroughIntoType(true, &calls) == 101)
    Swag.require(calls == 0)

    Swag.require(fallthroughIntoType(5's32, &calls) == 10)
    Swag.require(calls == 1)
}

// A failed test after fallthrough resumes after the switch, even if its default ran first.
func typedFallthroughAfterDefault(value: const any)->s32
{
    switch value
    {
    case bool: return 1
    default:   fallthrough
    case s32:  return 2
    }
    return 3
}

func bindingFallthroughAfterDefault(value: *s32?, advance: bool)->s32
{
    switch
    {
    default:
        if advance do
            fallthrough
        else do
            return 1
    case let item = value: return item[]
    }
    return 3
}

#test
{
    var value = 5
    Swag.require(typedFallthroughAfterDefault(true) == 1)
    Swag.require(typedFallthroughAfterDefault(7.5) == 3)
    Swag.require(typedFallthroughAfterDefault(2) == 2)
    Swag.require(bindingFallthroughAfterDefault(null, false) == 1)
    Swag.require(bindingFallthroughAfterDefault(null, true) == 3)
    Swag.require(bindingFallthroughAfterDefault(&value, true) == 5)
}
