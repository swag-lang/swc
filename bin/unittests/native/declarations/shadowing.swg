#global private

// Variable shadowing in nested scopes.

// Inner block shadows outer variable.
#test
{
    var x = 10
    scope
    {
        var x = 20
        Swag.require(x == 20)
    }
    Swag.require(x == 10)
}

// Shadowing in if block.
#test
{
    var value = 1
    if true
    {
        var value = 2
        Swag.require(value == 2)
    }
    Swag.require(value == 1)
}

// Shadowing in for loop.
#test
{
    var sum = 0
    for i in 3
    {
        var sum = i * 10
        Swag.require(sum == i * 10)
    }
    Swag.require(sum == 0)
}

// Multiple levels of shadowing.
#test
{
    var x = 1
    scope
    {
        var x = 2
        scope
        {
            var x = 3
            Swag.require(x == 3)
        }
        Swag.require(x == 2)
    }
    Swag.require(x == 1)
}

// Shadow with different types.
#test
{
    var v: s32 = 42
    scope
    {
        var v: f64 = 3.14
        Swag.require(v == 3.14)
    }
    Swag.require(v == 42)
}

// Shadow in while loop.
#test
{
    var count = 100
    var i     = 0
    while i < 3
    {
        var count = i
        Swag.require(count == i)
        i += 1
    }
    Swag.require(count == 100)
}
