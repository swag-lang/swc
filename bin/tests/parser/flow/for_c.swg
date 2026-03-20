#global fileprivate

func for_c_control_flow_ok()
{
    for var i = 0; i < 3; i += 1
    {
    }

    for var i = 0; i < 1; i += 1
    {
        for var j = 0; j < 2; j += 1
        {
            var k = i + j
        }
    }

    return
}

#test
{
    var total = 0
    for var i = 0; i < 5; i += 1
    {
        total += i
    }

    for var x = 0; x != 0; x += 1
    {
        break
    }
}
