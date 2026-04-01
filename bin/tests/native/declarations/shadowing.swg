#global fileprivate

// Variable shadowing in nested scopes.

// Inner block shadows outer variable.
#test
{
    var x = 10
    {
        var x = 20
        @assert(x == 20)
    }
    @assert(x == 10)
}

// Shadowing in if block.
#test
{
    var value = 1
    if true
    {
        var value = 2
        @assert(value == 2)
    }
    @assert(value == 1)
}

// Shadowing in for loop.
#test
{
    var sum = 0
    for i in 3
    {
        var sum = i * 10
        @assert(sum == i * 10)
    }
    @assert(sum == 0)
}

// Multiple levels of shadowing.
#test
{
    var x = 1
    {
        var x = 2
        {
            var x = 3
            @assert(x == 3)
        }
        @assert(x == 2)
    }
    @assert(x == 1)
}

// Shadow with different types.
#test
{
    var v: s32 = 42
    {
        var v: f64 = 3.14
        @assert(v == 3.14)
    }
    @assert(v == 42)
}

// Shadow in while loop.
#test
{
    var count = 100
    var i = 0
    while i < 3
    {
        var count = i
        @assert(count == i)
        i += 1
    }
    @assert(count == 100)
}
