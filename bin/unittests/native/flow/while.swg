#global private

#test
{
    var i = 0
    while i < 3
    {
        var x = 0
        i += 1
    }
    Swag.assert(i == 3)
}

#test
{
    var count = 0
    while count < 4
    {
        var x = 0
        count += 1
    }

    Swag.assert(count == 4)
}

#test
{
    var outer = 0
    while outer < 2
    {
        var inner = 0
        while inner < 3
        {
            var x = 0
            inner += 1
        }

        outer += 1
    }

    Swag.assert(outer == 2)
}
