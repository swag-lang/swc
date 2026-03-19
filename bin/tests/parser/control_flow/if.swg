#global fileprivate

func if_control_flow_ok()
{
    if true
    {
    }

    if false
    {
    }
    else
    {
    }

    if false
    {
    }
    elif true
    {
    }
    else
    {
    }

    if var x = 0
    {
    }

    if var y = 0 where y == 0
    {
        y = 1
    }
    else
    {
        y = 2
    }

    return
}

#test
{
    if true
    {
        var a = 1
    }

    if false
    {
    }

    if false
    {
        var c = 0
    }
    elif true
    {
        var d = 1
    }

    if var n = 1
    {
        var m = n
    }
}
