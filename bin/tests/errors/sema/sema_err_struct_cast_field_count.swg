#global fileprivate

struct Vec3I {x, y, z: s32}
struct Simple2 {x: s32, y: s32}
struct Simple3 {x: s32, y: s32, z: s32}

#test { const VEC3I: Vec3I = {1, 2, 3, 4} } // swc-expected-error {{sema_err_struct_cast_field_count}}

#test
{
    const SIMPLE2A: Simple2 = {1, 2}
    const SIMPLE3: Simple3 = SIMPLE2A // swc-expected-error {{sema_err_struct_cast_field_count}}
}
