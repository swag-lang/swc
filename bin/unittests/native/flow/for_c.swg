#global private

#test
{
    var sum = 0
    for var i = 0; i < 3; i += 1
    {
        sum += i
    }
    Swag.assert(sum == 3)
}

#test
{
    var count = 0
    var last  = -1
    for var i = 0; i < 1; i += 1
    {
        var x = i
        last  = x
        count += 1
    }
    Swag.assert(count == 1)
    Swag.assert(last == 0)
}
