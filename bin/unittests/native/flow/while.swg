#global private

#test
{
    var i = 0
    while i < 3
    {
        var x = 0
        discard x
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
        discard x
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
            discard x
            inner += 1
        }

        outer += 1
    }

    Swag.assert(outer == 2)
}
