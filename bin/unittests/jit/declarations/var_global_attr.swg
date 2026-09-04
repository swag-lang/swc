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

// A function-local `global` owns ONE storage for the whole program, so a body that declares one
// cannot be cloned into its call sites. Marking it `#[Swag.Inline]` must not change that: each
// copy would count on a storage of its own.
#test
{
    #[Swag.Inline]
    func marked()->s32
    {
        global var value = 100
        value += 1
        return value
    }

    Swag.assert(marked() == 101)
    Swag.assert(marked() == 102)
    Swag.assert(marked() == 103)
}
