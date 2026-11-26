#global private

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
    else if true
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

    if let a = 1
    {
    }

    if let b = 1 where b == 1
    {
    }

    if let c = 4 where c > 2 {
        return
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
    else if true
    {
        var d = 1
    }

    if var n = 1
    {
        var m = n
    }

    if let p = 2
    {
        var q = p
    }

    if let r = 4 where r > 2 {
        var s = r
}
}
