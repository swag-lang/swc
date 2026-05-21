#global fileprivate

#[Swag.Compiler]
func expectCompilerOnlyCall(value: string)->s32
{
    @assert(value == "inside compiler-only run call")
    return 42
}

const PrefixValue = #run
{
    return expectCompilerOnlyCall("inside compiler-only run call")
}

const PrefixValueAgain = #run
{
    let base = PrefixValue - 2
    return base + 2
}

struct(T, Count: s32) GuardedVector
    where
    {
        if PrefixValueAgain == 42 and Count >= 2 and (T == s32 or T == s64) do
            return true
        return false
    }
{
    values: [Count] T
}

#test
{
    let values: GuardedVector'(s32, 3) = {values: [1, 2, 3]}
    @assert(#typeof(values.values) == [3] s32)
    @assert(values.values[0] == 1)
    @assert(values.values[2] == 3)
}
