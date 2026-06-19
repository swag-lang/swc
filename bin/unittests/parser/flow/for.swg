#global fileprivate

func for_control_flow_ok()
{
    for 3
    {
        var x = 0
    }

    for i in 3
    {
        var y = i
    }

    for i in 1 to 5
    {
        var z = i
    }

    for i in 10 where i > 5
    {
        var w = i
    }

    return
}

#test
{
    for 5
    {
    }

    for i in 10
    {
        for j in 2
        {
            var x = i
            var y = j
        }
    }

    for i in 0 until 4
    {
        var sum = i
    }

    for #reverse i in 3 to 8
    {
        var value = i
    }
}
