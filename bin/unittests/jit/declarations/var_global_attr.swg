#global private

#test
{
    func counter()->s32
    {
        global var count = 0
        count += 1
        return count
    }

    Swag.assert(counter() == 1)
    Swag.assert(counter() == 2)
    Swag.assert(counter() == 3)
}

#test
{
    func accumulate(v: s32)->s32
    {
        global var total: s32 = 0
        total += v
        return total
    }

    Swag.assert(accumulate(10) == 10)
    Swag.assert(accumulate(20) == 30)
    Swag.assert(accumulate(5) == 35)
}

#test
{
    func toggle()->bool
    {
        global var state = false
        state = !state
        return state
    }

    Swag.assert(toggle() == true)
    Swag.assert(toggle() == false)
    Swag.assert(toggle() == true)
}
