#global private
var LogCounter: s32

func sideEffect(flag: bool, delta: s32)->bool
{
    LogCounter += delta
    return flag
}

// Logical and/or truth table with literals
#test
{
    Swag.require(true and true)
    Swag.require(not (true and false))
    Swag.require(not (false and true))
    Swag.require(not (false and false))

    Swag.require(true or true)
    Swag.require(true or false)
    Swag.require(false or true)
    Swag.require(not (false or false))
}

// Logical and/or truth table with variables
#test
{
    let t = true
    let f = false
    Swag.require(t and t)
    Swag.require(not (t and f))
    Swag.require(not (f and t))
    Swag.require(not (f and f))
    Swag.require(t or t)
    Swag.require(t or f)
    Swag.require(f or t)
    Swag.require(not (f or f))
}

// Logical operators with comparison subexpressions
#test
{
    let a = 5 > 3 and 2 < 4
    let b = 5 > 3 and 2 > 4
    let c = 5 < 3 or 2 < 4
    let d = 5 < 3 or 2 > 4

    #assert(#typeof(a) == bool)
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
    #assert(#typeof(d) == bool)

    Swag.require(a)
    Swag.require(not b)
    Swag.require(c)
    Swag.require(not d)
}

// and short-circuits: right side must not be evaluated when left is false
#test
{
    LogCounter = 0
    let a = sideEffect(false, 1) and sideEffect(true, 10)
    Swag.require(not a)
    Swag.require(LogCounter == 1)
}

// or short-circuits: right side must not be evaluated when left is true
#test
{
    LogCounter = 0
    let b = sideEffect(true, 1) or sideEffect(true, 10)
    Swag.require(b)
    Swag.require(LogCounter == 1)
}

// no short-circuit when left is true for and
#test
{
    LogCounter = 0
    let a = sideEffect(true, 1) and sideEffect(true, 10)
    Swag.require(a)
    Swag.require(LogCounter == 11)
}

// no short-circuit when left is false for or
#test
{
    LogCounter = 0
    let b = sideEffect(false, 1) or sideEffect(true, 10)
    Swag.require(b)
    Swag.require(LogCounter == 11)
}

// Chained logical operators
#test
{
    let a = true and true and true
    let b = true and false and true
    let c = false or false or true
    let d = false or false or false

    Swag.require(a)
    Swag.require(not b)
    Swag.require(c)
    Swag.require(not d)
}

// Mixed and/or with parenthesized grouping
#test
{
    let a = (true or false) and (false or true)
    let b = (false and true) or (true and false)
    let c = true and (false or true) and (true or false)

    Swag.require(a)
    Swag.require(not b)
    Swag.require(c)
}

func logicalValueProbe(value: s64, delta: s32)->s64
{
    LogCounter += delta
    return value
}

func logicalFloatProbe(value: f32, delta: s32)->f32
{
    LogCounter += delta
    return value
}

// Non-bool lhs truthiness must still short-circuit `or`
#test
{
    LogCounter = 0
    let value = logicalValueProbe(3, 1) or sideEffect(true, 10)
    Swag.require(value)
    Swag.require(LogCounter == 1)
}

// Non-bool lhs truthiness must still short-circuit `and`
#test
{
    LogCounter = 0
    let value = logicalValueProbe(0, 1) and sideEffect(true, 10)
    Swag.require(not value)
    Swag.require(LogCounter == 1)
}

// Falsey non-bool lhs must evaluate rhs for `or`
#test
{
    LogCounter = 0
    let value = logicalValueProbe(0, 1) or sideEffect(true, 10)
    Swag.require(value)
    Swag.require(LogCounter == 11)
}

// Float truthiness follows the same zero/non-zero short-circuit rules
#test
{
    LogCounter = 0
    let value = logicalFloatProbe(0.0'f32, 1) or sideEffect(true, 10)
    Swag.require(value)
    Swag.require(LogCounter == 11)
}

#test
{
    LogCounter = 0
    let value = logicalFloatProbe(2.0'f32, 1) or sideEffect(true, 10)
    Swag.require(value)
    Swag.require(LogCounter == 1)
}

// Truthy non-bool lhs must evaluate rhs for `and`
#test
{
    LogCounter = 0
    let value = logicalValueProbe(2, 1) and sideEffect(true, 10)
    Swag.require(value)
    Swag.require(LogCounter == 11)
}

struct LogicalNullableGuardItem
{
    value: s32
}

impl LogicalNullableGuardItem
{
    mtd isExpected()->bool => .value == 17
}

func logicalNullableGuardOr(item: *LogicalNullableGuardItem?)->bool
{
    return not item or item.isExpected()
}

func logicalNullableGuardAnd(item: *LogicalNullableGuardItem?)->bool
{
    return item and item.isExpected()
}

func logicalNullableMaybe(p: *LogicalNullableGuardItem)->*LogicalNullableGuardItem? => p

#test
{
    var item = LogicalNullableGuardItem{value: 17}
    let ptr:   *LogicalNullableGuardItem? = logicalNullableMaybe(&item)
    let empty: *LogicalNullableGuardItem? = null

    Swag.require(logicalNullableGuardOr(empty))
    Swag.require(logicalNullableGuardOr(ptr))
    Swag.require(not logicalNullableGuardAnd(empty))
    Swag.require(logicalNullableGuardAnd(ptr))
}
