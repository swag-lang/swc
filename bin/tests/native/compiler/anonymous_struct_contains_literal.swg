#global moduleprivate
using Swag

#test
{
    var value: struct { x: s32; y: s32 }
    value = {1, 2}

    @assert(value == {1, 2})
    @assert(value != {2, 1})
}
