#global fileprivate // swc-option suite-test

#test
{
    var sum = 0
    for var i = 0; i < 3; i += 1
    {
        sum += i
    }
}

#test
{
    for var i = 0; i < 1; i += 1
    {
        var x = i
    }

}

