#global private

#test
{
    func counter()->s32
    {
        global var count = 0
        count += 1
        return count
    }

    Swag.require(counter() == 1)
    Swag.require(counter() == 2)
    Swag.require(counter() == 3)
}

#test
{
    func accumulate(v: s32)->s32
    {
        global var total: s32 = 0
        total += v
        return total
    }

    Swag.require(accumulate(10) == 10)
    Swag.require(accumulate(20) == 30)
    Swag.require(accumulate(5) == 35)
}

#test
{
    func toggle()->bool
    {
        global var state = false
        state = not state
        return state
    }

    Swag.require(toggle() == true)
    Swag.require(toggle() == false)
    Swag.require(toggle() == true)
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

    Swag.require(marked() == 101)
    Swag.require(marked() == 102)
    Swag.require(marked() == 103)
}
