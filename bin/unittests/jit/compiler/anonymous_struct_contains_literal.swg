#global internal
using Swag

#test
{
    func checkCompare()->bool
    {
        var value: struct { x: s32; y: s32 }
        value = {1, 2}
        return value == {1, 2} and value != {2, 1}
    }

    const V = #run checkCompare()
    #assert(V)
}