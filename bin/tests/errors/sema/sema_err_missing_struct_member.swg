#global fileprivate

struct Vec3I {x, y, z: s32}

#test { const VEC3I: Vec3I = {x: 1, q: 2, z: 3} } // swc-expected-error {{sema_err_missing_struct_member}}
