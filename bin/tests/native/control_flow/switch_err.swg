#global fileprivate // swc-option suite-test

#test
{
    var v = 1
    var hit = 0
    switch v
    {
        default:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var hit = 0
    switch 1
    {
        case 1:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 1)
}

#test
{
    var v = 2
    var hit = 0
    switch v
    {
        default:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var a : [4] s32
    var hit = 0
    switch
    {
        default:
            hit = 1
            break
    }
    @assert(hit == 1)
}


#test
{
    var b = "hello"
    var hit = 0
    switch b
    {
        default:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var a = 2
    var hit = 0
    switch a
    {
    case 1 where true:
        hit = 1
        break
    }
    @assert(hit == 0)
}

#test
{
    var hit = 0
    switch 1
    {
        default:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var hit = 0
    switch 1
    {
        default where true:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var hit = 0
    switch 1
    {
        default where false:
            hit = 1
            break
        default:
            hit = 2
            break
    }
    @assert(hit == 2)
}

#test
{
    var hit = 0
    switch 1
    {
        default where false:
            hit = 1
            break
        default where 1 < 2:
            hit = 2
            break
    }
    @assert(hit == 2)
}

#test
{
    var hit = 0
    #[Swag.Complete]
    switch 1
    {
        case 1:
            hit = 1
            break
    }
    @assert(hit == 1)
}

#test
{
    var hit = 0
    #[Swag.Complete]
    switch 1
    {
        case 1:
            hit = 1
            break
        default where false:
            hit = 2
            break
    }
    @assert(hit == 1)
}
