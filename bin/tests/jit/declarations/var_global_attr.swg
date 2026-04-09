#global fileprivate

#test
{
    func counter()->s32
    {
        #[Swag.Global]
        var count = 0
        count += 1
        return count
    }

    @assert(counter() == 1)
    @assert(counter() == 2)
    @assert(counter() == 3)
}

#test
{
    func accumulate(v: s32)->s32
    {
        #[Swag.Global]
        var total: s32 = 0
        total += v
        return total
    }

    @assert(accumulate(10) == 10)
    @assert(accumulate(20) == 30)
    @assert(accumulate(5) == 35)
}

#test
{
    func toggle()->bool
    {
        #[Swag.Global]
        var state = false
        state = !state
        return state
    }

    @assert(toggle() == true)
    @assert(toggle() == false)
    @assert(toggle() == true)
}
