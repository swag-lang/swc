#global fileprivate

struct Vec3I {x, y, z: s32}

// Using an unknown field name in a struct literal is reported, whether alone or mixed with valid fields.
#test
{
    const a: Vec3I = {x: 1, q: 2, z: 3}      // swc-expected-error {{sema_err_missing_struct_member}}
}

#test
{
    const b: Vec3I = {foo: 1}                // swc-expected-error {{sema_err_missing_struct_member}}
}

#test
{
    const c: Vec3I = {x: 1, y: 2, z: 3, w: 4}        // swc-expected-error {{sema_err_missing_struct_member}}
}
