// swc-option suite-test

#global fileprivate
using Swag

func main()->s32
{
    var a = 10
    while a > 0
    {
        a -= 1; if (a == 5) do
            break
        continue
    }
    @assert(a == 5)
    return a
}

#test
{
    @assert(main() == 5)
}
