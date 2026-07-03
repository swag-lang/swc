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
    @assert(true and true)
    @assert(!(true and false))
    @assert(!(false and true))
    @assert(!(false and false))

    @assert(true or true)
    @assert(true or false)
    @assert(false or true)
    @assert(!(false or false))
}

// Logical and/or truth table with variables
#test
{
    let t = true
    let f = false
    @assert(t and t)
    @assert(!(t and f))
    @assert(!(f and t))
    @assert(!(f and f))
    @assert(t or t)
    @assert(t or f)
    @assert(f or t)
    @assert(!(f or f))
}

// Logical operators with comparison subexpressions
#test
{
    let a = 5 > 3 and 2 < 4
    let b = 5 > 3 and 2 > 4
    let c = 5 < 3 or  2 < 4
    let d = 5 < 3 or  2 > 4

    #assert(#typeof(a) == bool)
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
    #assert(#typeof(d) == bool)

    @assert(a)
    @assert(!b)
    @assert(c)
    @assert(!d)
}

// and short-circuits: right side must not be evaluated when left is false
#test
{
    LogCounter = 0
    let a = sideEffect(false, 1) and sideEffect(true, 10)
    @assert(!a)
    @assert(LogCounter == 1)
}

// or short-circuits: right side must not be evaluated when left is true
#test
{
    LogCounter = 0
    let b = sideEffect(true, 1) or sideEffect(true, 10)
    @assert(b)
    @assert(LogCounter == 1)
}

// no short-circuit when left is true for and
#test
{
    LogCounter = 0
    let a = sideEffect(true, 1) and sideEffect(true, 10)
    @assert(a)
    @assert(LogCounter == 11)
}

// no short-circuit when left is false for or
#test
{
    LogCounter = 0
    let b = sideEffect(false, 1) or sideEffect(true, 10)
    @assert(b)
    @assert(LogCounter == 11)
}

// Chained logical operators
#test
{
    let a = true and true and true
    let b = true and false and true
    let c = false or false or true
    let d = false or false or false

    @assert(a)
    @assert(!b)
    @assert(c)
    @assert(!d)
}

// Mixed and/or with parenthesized grouping
#test
{
    let a = (true or false) and (false or true)
    let b = (false and true) or (true and false)
    let c = true and (false or true) and (true or false)

    @assert(a)
    @assert(!b)
    @assert(c)
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
    @assert(value)
    @assert(LogCounter == 1)
}

// Non-bool lhs truthiness must still short-circuit `and`
#test
{
    LogCounter = 0
    let value = logicalValueProbe(0, 1) and sideEffect(true, 10)
    @assert(!value)
    @assert(LogCounter == 1)
}

// Falsey non-bool lhs must evaluate rhs for `or`
#test
{
    LogCounter = 0
    let value = logicalValueProbe(0, 1) or sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 11)
}

// Float truthiness follows the same zero/non-zero short-circuit rules
#test
{
    LogCounter = 0
    let value = logicalFloatProbe(0.0'f32, 1) or sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 11)
}

#test
{
    LogCounter = 0
    let value = logicalFloatProbe(2.0'f32, 1) or sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 1)
}

// Truthy non-bool lhs must evaluate rhs for `and`
#test
{
    LogCounter = 0
    let value = logicalValueProbe(2, 1) and sideEffect(true, 10)
    @assert(value)
    @assert(LogCounter == 11)
}

struct LogicalNullableGuardItem
{
    value: s32
}

impl LogicalNullableGuardItem
{
    mtd isExpected()->bool => .value == 17
}

func logicalNullableGuardOr(item: #null *LogicalNullableGuardItem)->bool
{
    return !item or item.isExpected()
}

func logicalNullableGuardAnd(item: #null *LogicalNullableGuardItem)->bool
{
    return item and item.isExpected()
}

#test
{
    var item = LogicalNullableGuardItem{value: 17}
    let ptr: #null *LogicalNullableGuardItem = &item
    let empty: #null *LogicalNullableGuardItem = null

    @assert(logicalNullableGuardOr(empty))
    @assert(logicalNullableGuardOr(ptr))
    @assert(!logicalNullableGuardAnd(empty))
    @assert(logicalNullableGuardAnd(ptr))
}
