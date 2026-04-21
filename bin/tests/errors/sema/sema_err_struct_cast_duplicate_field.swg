#global fileprivate

struct Vec3I {x, y, z: s32}

#test { const VEC3I: Vec3I = {x: 1, x: 2, z: 3} } // swc-expected-error {{sema_err_struct_cast_duplicate_field}}
#test { const VEC3I: Vec3I = {1, x: 2, y: 3} } // swc-expected-error {{sema_err_struct_cast_duplicate_field}}
