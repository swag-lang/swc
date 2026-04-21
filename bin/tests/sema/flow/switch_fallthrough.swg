#global fileprivate

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
