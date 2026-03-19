#global fileprivate // 

#test
{
    var v = 1
    var hit = 0
    switch v
    {
        case 1:
            hit += 1
            fallthrough
        case 2:
            hit += 10
            break
        default:
            hit += 100
            break
    }
    @assert(hit == 11)
}


#test
{
    var v = 1
    var hit = 0
    switch v
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
    var v = 0
    var hit = 0
    switch v
    {
        case 0:
            hit += 1
            fallthrough
        case 1:
            hit += 10
            fallthrough
        case 2:
            hit += 100
            break
    }
    @assert(hit == 111)
}

#test
{
    var v = 0
    var hit = 0
    switch v
    {
        case 0:
            var a = 1
            hit = a
        case 1:
            hit += 10
            break
    }
    @assert(hit == 1)
}
