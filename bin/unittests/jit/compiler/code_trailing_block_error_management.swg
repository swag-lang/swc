#global private

// A fallible macro still takes its trailing '{ ... }' block when the call carries its
// error-management keyword: 'expect f(x) { ... }', 'try f(x) { ... }', and
// 'catch f(x) { ... }' pass the block to 'f' exactly as a bare 'f(x) { ... }' does.

struct TrailingBlockError
{
    using base: Swag.BaseError
}

#[Swag.Macro]
func visitUpTo(count, failAt: s32, stmt: #code(index: s32)) fail
{
    for i in count
    {
        if i == failAt do
            fail TrailingBlockError{}
        #inject(stmt, index = i)
    }
}

func sumWithTry(count: s32)->s32 fail
{
    var total = 0
    try visitUpTo(count, -1)
    {
        total += index
    }

    return total
}

#test
{
    var total = 0
    expect visitUpTo(4, -1)
    {
        total += index
    }

    Swag.assert(total == 6)
    Swag.assert(expect sumWithTry(5) == 10)

    // The block runs for the indices reached before the failure, then 'catch' dismisses it.
    var reached = 0
    catch visitUpTo(10, 3)
    {
        reached += 1
    }

    Swag.assert(reached == 3)
}
