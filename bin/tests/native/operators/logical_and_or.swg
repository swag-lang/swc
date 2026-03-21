#global fileprivate //

var LogCounter: s32

func sideEffect(flag: bool, delta: s32)->bool
{
    LogCounter += delta
    return flag
}

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

#test
{
    let a = (true or false) and (false or true)
    let b = (false and true) or (true and false)
    let c = true and (false or true) and (true or false)

    @assert(a)
    @assert(!b)
    @assert(c)
}
