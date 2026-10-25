#global internal
using Swag

#test
{
    func checkCompare()->bool
    {
        var value: struct { x: s32; y: s32 }
        value = {x: 1, y: 2}
        return value == {x: 1, y: 2} and value != {x: 2, y: 1}
    }

    const V = #run checkCompare()
    #assert(V)
}
