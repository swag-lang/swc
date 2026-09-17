#global private
using Swag

// A struct of floats passed by value arrives in one register. Its fields are
// moved out of that register instead of reloaded from memory: a pair of f32
// read in any order, compared, a double filling the word, and a mixed pair
// whose integer half is read too.

struct Vec2
{
    x, y: f32
}

struct Wrapper
{
    v: f64
}

struct Tagged
{
    weight: f32
    id:     u32
}

#[Swag.Optimize(true), Swag.NoInline]
func dot(a, b: Vec2)->f32 => a.x * b.x + a.y * b.y

#[Swag.Optimize(true), Swag.NoInline]
func cross(a, b: Vec2)->f32 => a.x * b.y - a.y * b.x

#[Swag.Optimize(true), Swag.NoInline]
func longer(a: Vec2)->bool => a.y > a.x

#[Swag.Optimize(true), Swag.NoInline]
func unwrap(w: Wrapper)->f64 => w.v * 2

#[Swag.Optimize(true), Swag.NoInline]
func score(t: Tagged)->f32 => t.weight * cast(f32) t.id

#test
{
    Swag.assert(dot(Vec2{1, 2}, Vec2{3, 4}) == 11)
    Swag.assert(dot(Vec2{-1.5, 0.5}, Vec2{2, -4}) == -5)
    Swag.assert(cross(Vec2{1, 2}, Vec2{3, 4}) == -2)
    Swag.assert(longer(Vec2{1, 2}))
    Swag.assert(not longer(Vec2{-1, -2}))
    Swag.assert(unwrap(Wrapper{-2.25}) == -4.5)
    Swag.assert(score(Tagged{0.5, 6}) == 3)
}
