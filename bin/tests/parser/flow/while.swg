#global fileprivate

func while_control_flow_ok()
{
    while false
    {
    }

    while true
    {
        break
    }

    return
}

#test
{
    while false
    {
    }

    while true
    {
        while false
        {
            var a = 0
        }
        break
    }

    var counter = 0
    while counter < 3
    {
        counter += 1
    }
}
