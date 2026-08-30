#global internal
using Swag

#test
{
    var value: struct { x: s32; y: s32 }
    value = {1, 2}

    Swag.assert(value == {1, 2})
    Swag.assert(value != {2, 1})
}
