#global private

#[Swag.Macro]
func invokeBinding(callback: func||()->s32)->s32 => callback()

#test
{
    let seed   = 3
    let result = invokeBinding(func|seed|()->s32
    {
        func double(value: s32)->s32 => value * 2

        // The binding contains enough nodes to promote the shared visited set,
        // including a nested callable with its own parameter scope.
        var total = 0
        total += seed
        total += seed
        total += seed
        total += seed
        total += seed
        total += seed
        total += seed
        total += seed
        total += seed
        total += seed
        total += seed
        total += seed
        return double(total)
    })
    Swag.assert(result == 72)
}
