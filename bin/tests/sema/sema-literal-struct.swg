#global internal

const ANONYMOUS = {1's32, 2}

struct Vec3F {x, y, z: f32}
const VEC3F_TYPED: Vec3F = {10, 5, 2}
#assert(VEC3F_TYPED.x == 10)
#assert(VEC3F_TYPED.y == 5)
#assert(VEC3F_TYPED.z == 2)
#assert(#typeof(VEC3F_TYPED) == Vec3F)

const VEC3F_INFERRED = {x: 10, y: 5, z: 2}
#assert(VEC3F_INFERRED.x == 10)
#assert(VEC3F_INFERRED.y == 5)
#assert(VEC3F_INFERRED.z == 2)

const MIXED_NAMED_UNNAMED = {10, y: 5, 2}
#assert(MIXED_NAMED_UNNAMED.item0 == 10)
#assert(MIXED_NAMED_UNNAMED.y == 5)
#assert(MIXED_NAMED_UNNAMED.item2 == 2)
#assert(MIXED_NAMED_UNNAMED.item2 != 20)

struct Vec3I {x, y, z: s32}
struct Simple2 {x: s32, y: s32}
struct Simple3 {x: s32, y: s32, z: s32}
struct Single1 {x: s32}
struct Single2 {x: f32}

#test
{
    const VEC3I: Vec3I = {y: 2, x: 1, z: 3}
    #assert(VEC3I.x == 1)
    #assert(VEC3I.y == 2)
    #assert(VEC3I.z == 3)
}

#test
{
    const VEC3I: Vec3I = {1, z: 3, y: 2}
    #assert(VEC3I.x == 1)
    #assert(VEC3I.y == 2)
    #assert(VEC3I.z == 3)
}

#test
{
    const VEC3I: Vec3I = {1, 2}
    #assert(VEC3I.x == 1)
    #assert(VEC3I.y == 2)
    #assert(VEC3I.z == 0)
}

#test { const VEC3I: Vec3I = {x: 1, 2, z: 3} } // swc-expected-error {{sema_err_unnamed_parameter}}
#test { const VEC3I: Vec3I = {x: 1, q: 2, z: 3} } // swc-expected-error {{sema_err_missing_struct_member}}
#test { const VEC3I: Vec3I = {x: 1, x: 2, z: 3} } // swc-expected-error {{sema_err_struct_cast_duplicate_field}}
#test { const VEC3I: Vec3I = {1, x: 2, y: 3} } // swc-expected-error {{sema_err_struct_cast_duplicate_field}}
#test { const VEC3I: Vec3I = {1, 2, 3, 4} } // swc-expected-error {{sema_err_struct_cast_field_count}}

struct InvalidCast {x: s32, y: s32}
#test { const INVALID: InvalidCast = {1, "no"} } // swc-expected-error {{sema_err_cannot_cast}}

#test
{
    const SIMPLE2A: Simple2 = {1, 2}
    const SIMPLE3: Simple3 = SIMPLE2A // swc-expected-error {{sema_err_struct_cast_field_count}}
}

#test
{
    const SINGLE1: Single1 = {1}
    const SINGLE2: Single2 = SINGLE1 // swc-expected-error {{sema_err_struct_cast_field_type}}
}

struct Vec3FDefault {x, y, z: f32 = 10}
const VEC3F_DEFAULTS: Vec3FDefault = {x: 1, y: 1}
#assert(VEC3F_DEFAULTS.z == 10)

const VEC3F_PARTIAL: Vec3FDefault = {1, 2}
#assert(VEC3F_PARTIAL.x == 1)
#assert(VEC3F_PARTIAL.y == 2)
#assert(VEC3F_PARTIAL.z == 10)

const VEC3F_ALL_DEFAULTS: Vec3FDefault
#assert(VEC3F_ALL_DEFAULTS.x == 10)
#assert(VEC3F_ALL_DEFAULTS.y == 10)
#assert(VEC3F_ALL_DEFAULTS.z == 10)

const VEC3F_CAST_SYNTAX: Vec3FDefault{1, 2}
#assert(VEC3F_CAST_SYNTAX.x == 1)
#assert(VEC3F_CAST_SYNTAX.y == 2)
#assert(VEC3F_CAST_SYNTAX.z == 10)

const VEC3F_NAMED_CAST: Vec3FDefault = Vec3FDefault{5, 7}
#assert(VEC3F_NAMED_CAST.x == 5)
#assert(VEC3F_NAMED_CAST.y == 7)
#assert(VEC3F_NAMED_CAST.z == 10)
struct Point {x, y: s32}
struct Rect {topLeft: Point, bottomRight: Point}

#test
{
    const RECT: Rect = {{1, 2}, {3, 4}}
    #assert(RECT.topLeft.x == 1)
    #assert(RECT.topLeft.y == 2)
    #assert(RECT.bottomRight.x == 3)
    #assert(RECT.bottomRight.y == 4)
}

#test
{
    const RECT: Rect = {topLeft: {x: 1, y: 2}, bottomRight: {x: 3, y: 4}}
    #assert(RECT.topLeft.x == 1)
    #assert(RECT.topLeft.y == 2)
    #assert(RECT.bottomRight.x == 3)
    #assert(RECT.bottomRight.y == 4)
}

#test
{
    const RECT: Rect = {topLeft: {1, 2}, bottomRight: {3, 4}}
    #assert(RECT.topLeft.x == 1)
    #assert(RECT.topLeft.y == 2)
    #assert(RECT.bottomRight.x == 3)
    #assert(RECT.bottomRight.y == 4)
}

#test
{
    const RECT: Rect = {{x: 1, y: 2}, {x: 3, y: 4}}
    #assert(RECT.topLeft.x == 1)
    #assert(RECT.topLeft.y == 2)
    #assert(RECT.bottomRight.x == 3)
    #assert(RECT.bottomRight.y == 4)
}

struct Color {r, g, b: u8 = 0}
struct Vertex {pos: Point, color: Color}

#test
{
    const VERTEX: Vertex = {{5, 10}, {255, 128, 64}}
    #assert(VERTEX.pos.x == 5)
    #assert(VERTEX.pos.y == 10)
    #assert(VERTEX.color.r == 255)
    #assert(VERTEX.color.g == 128)
    #assert(VERTEX.color.b == 64)
}

#test
{
    const VERTEX: Vertex = {{5, 10}, {255, 128}}
    #assert(VERTEX.pos.x == 5)
    #assert(VERTEX.pos.y == 10)
    #assert(VERTEX.color.r == 255)
    #assert(VERTEX.color.g == 128)
    #assert(VERTEX.color.b == 0)
}

#test
{
    const VERTEX: Vertex = {pos: {x: 5, y: 10}, color: {r: 255, g: 128, b: 64}}
    #assert(VERTEX.pos.x == 5)
    #assert(VERTEX.pos.y == 10)
    #assert(VERTEX.color.r == 255)
    #assert(VERTEX.color.g == 128)
    #assert(VERTEX.color.b == 64)
}

#test
{
    const VERTEX: Vertex = {pos: {1, 2}, color: {}}
    #assert(VERTEX.pos.x == 1)
    #assert(VERTEX.pos.y == 2)
    #assert(VERTEX.color.r == 0)
    #assert(VERTEX.color.g == 0)
    #assert(VERTEX.color.b == 0)
}

struct Transform {pos: Point, scale: Vec3F}
struct Entity {name: Simple2, transform: Transform}

#test
{
    const ENTITY: Entity = {{10, 20}, {{100, 200}, {1, 2, 3}}}
    #assert(ENTITY.name.x == 10)
    #assert(ENTITY.name.y == 20)
    #assert(ENTITY.transform.pos.x == 100)
    #assert(ENTITY.transform.pos.y == 200)
    #assert(ENTITY.transform.scale.x == 1)
    #assert(ENTITY.transform.scale.y == 2)
    #assert(ENTITY.transform.scale.z == 3)
}

#test
{
    const ENTITY: Entity = {name: {x: 10, y: 20}, transform: {pos: {x: 100, y: 200}, scale: {x: 1, y: 2, z: 3}}}
    #assert(ENTITY.name.x == 10)
    #assert(ENTITY.name.y == 20)
    #assert(ENTITY.transform.pos.x == 100)
    #assert(ENTITY.transform.pos.y == 200)
    #assert(ENTITY.transform.scale.x == 1)
    #assert(ENTITY.transform.scale.y == 2)
    #assert(ENTITY.transform.scale.z == 3)
}

/*
#test { const rect: Rect = {{1, 2}, {3}} } // swc-expected-error {{sema_err_struct_cast_field_count}}
*/
#test { const vertex: Vertex = {{5, 10}, {256, 128, 64}} } // swc1-expected-error {{sema_err_literal_overflow}}
