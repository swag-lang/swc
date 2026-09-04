#global private

// A `global` declared inside a function is one storage for the whole program. Automatic inlining
// clones a body into each call site, so without a guard every site counted on a storage of its
// own and this answered 1, 1, 1. The release configuration is the one that inlines automatically.

func counter()->s32
{
    global var count = 0
    count += 1
    return count
}

#[Swag.Inline]
func markedCounter()->s32
{
    global var value = 100
    value += 1
    return value
}

func accumulate(v: s32)->s32
{
    global var total: s32 = 0
    total += v
    return total
}

#test
{
    Swag.assert(counter() == 1)
    Swag.assert(counter() == 2)
    Swag.assert(counter() == 3)

    Swag.assert(markedCounter() == 101)
    Swag.assert(markedCounter() == 102)

    Swag.assert(accumulate(10) == 10)
    Swag.assert(accumulate(20) == 30)
}

// One call site in a loop always worked: the storage is shared because there is one copy of the
// body. Keep both shapes so a fix that only repairs the loop is not mistaken for a fix.
#test
{
    func looped()->s32
    {
        global var count = 0
        count += 1
        return count
    }

    var last = 0
    for i in 3 do
        last = looped()
    Swag.assert(last == 3)
}
