#global internal

const A = {1's32, 2}

struct V {x, y, z: f32}
const v: V = {10, 5, 2}
#assert(v.x == 10)
#assert(v.y == 5)
#assert(v.z == 2)
#assert(#typeof(v) == V)

const v1 = {x: 10, y: 5, z: 2}
#assert(v1.x == 10)
#assert(v1.y == 5)
#assert(v1.z == 2)

const v2 = {10, y: 5, 2}
#assert(v2.item0 == 10)
#assert(v2.y == 5)
#assert(v2.item2 == 2)
#assert(v2.item2 != 20)

struct W {x, y, z: s32}
struct S1 {x: s32, y: s32}
struct S2 {x: s32, y: s32, z: s32}
struct T1 {x: s32}
struct T2 {x: f32}

#test
{
    const w: W = {y: 2, x: 1, z: 3}
    #assert(w.x == 1)
    #assert(w.y == 2)
    #assert(w.z == 3)
}

#test
{
    const w: W = {1, z: 3, y: 2}
    #assert(w.x == 1)
    #assert(w.y == 2)
    #assert(w.z == 3)
}

#test { const w: W = {x: 1, 2, z: 3} } // swc-expected-error {{sema_err_unnamed_parameter}}
#test { const w: W = {x: 1, q: 2, z: 3} } // swc-expected-error {{sema_err_missing_struct_member}}
#test { const w: W = {x: 1, x: 2, z: 3} } // swc-expected-error {{sema_err_struct_cast_duplicate_field}}
#test { const w: W = {1, 2, 3, 4} } // swc-expected-error {{sema_err_struct_cast_field_count}}

#test
{
    const a: S1 = {1, 2}
    const b: S2 = a // swc-expected-error {{sema_err_struct_cast_field_count}}
}

#test
{
    const a: T1 = {1}
    const b: T2 = a // swc-expected-error {{sema_err_struct_cast_field_type}}
}

struct V2 {x, y, z: f32 = 10}
const V3: V2 = {x: 1, y: 1}
#assert(V3.z == 10)