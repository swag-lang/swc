#global private

#test
{
    union U { x, y, z: f32 }
    let v = U{x: 42}
    Swag.assert(v.x == 42)
    Swag.assert(v.y == 42)
    Swag.assert(v.z == 42)
}

#test
{
    union IntOrFloat { i: s32, f: f32 }
    var u = IntOrFloat{i: 0x42280000's32}
    Swag.assert(u.i == 0x42280000's32)
    Swag.assert(#sizeof(IntOrFloat) == 4)
}

#test
{
    union Small { a: u8, b: u32 }
    Swag.assert(#sizeof(Small) == 4)
    var s = Small{b: 0xFF}
    Swag.assert(s.b == 0xFF)
}
