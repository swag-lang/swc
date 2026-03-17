// 

#global fileprivate
#test
{
    var state = 0
    if true
    {
        state += 1
    }

    if true
    {
        state += 10
    }

    if 1 + 1 == 2 + 1
    {
        state += 100
    }
    else
    {
        state += 1000
    }
    @assert(state == 1011)
}
