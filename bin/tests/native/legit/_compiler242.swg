// swc-option suite-test

#global fileprivate
using Swag

//#[PrintBc]
func main()->s32
{
    var a = 0
    while a < 10
    {
        a += 1;
        {
            {
                break
            }
        }
        @assert(false)
    }

    @assert(a == 1)
    return a
}

#test
{
    @assert(main() == 1)
}
