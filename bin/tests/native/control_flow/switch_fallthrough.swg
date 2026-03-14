#global fileprivate // swc-option suite-test

#test
{
    var v = 1
    switch v
    {
        case 1:
            fallthrough
        case 2:
            break
        default:
            break
    }
}


#test
{
    var v = 1
    switch v
    {
        case 1:
            break
        default:
            break
    }
}

#test
{
    var v = 0
    switch v
    {
        case 0:
            fallthrough
        case 1:
            fallthrough
        case 2:
            break
    }
}

#test
{
    var v = 0
    switch v
    {
        case 0:
            var a = 1
        case 1:
            break
    }
}
