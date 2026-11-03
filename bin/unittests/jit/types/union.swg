#global private

#test
{
    union U { x, y, z: f32 }
    let v = U{x: 42}
    Swag.require(v.x == 42)
    Swag.require(v.y == 42)
    Swag.require(v.z == 42)
}

#test
{
    union IntOrFloat { i: s32, f: f32 }
    var u = IntOrFloat{i: 0x42280000's32}
    Swag.require(u.i == 0x42280000's32)
    Swag.require(#sizeof(IntOrFloat) == 4)
}

#test
{
    union Small { a: u8, b: u32 }
    Swag.require(#sizeof(Small) == 4)
    var s = Small{b: 0xFF}
    Swag.require(s.b == 0xFF)
}
