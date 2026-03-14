#global fileprivate // swc-option suite-test

#test
{
    var v = 1
    switch v
    {
        default:
            break
    }
}

#test
{
    switch 1
    {
        case 1:
            break
        default:
            break
    }
}

#test
{
    var v = 2
    switch v
    {
        default:
            break
    }
}

#test
{
    var a : [4] s32
    switch
    {
        default:
            break
    }
}


#test
{
    var b = "hello"
    switch b
    {
        default:
            break
    }
}

#test
{
    var a = 2
    switch a
    {
    case 1 where true:
        break
    }
}

#test
{
    switch 1
    {
        default:
            break
    }
}

#test
{
    switch 1
    {
        default where true:
            break
    }
}

#test
{
    switch 1
    {
        default where false:
            break
        default:
            break
    }
}

#test
{
    switch 1
    {
        default where false:
            break
        default where 1 < 2:
            break
    }
}

#test
{
    #[Swag.Complete]
    switch 1
    {
        case 1:
            break
    }
}

#test
{
    #[Swag.Complete]
    switch 1
    {
        case 1:
            break
        default where false:
            break
    }
}
