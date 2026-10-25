#global internal
using Swag

#test
{
    var value: struct { x: s32; y: s32 }
    value = {x: 1, y: 2}

    Swag.assert(value == {x: 1, y: 2})
    Swag.assert(value != {x: 2, y: 1})
}
