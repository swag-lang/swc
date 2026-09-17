#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A chain of `and`s or `or`s exits early on the first decided test. Each
// exit jumps straight past the tests it has already decided, carrying the
// value the enclosing operators take from it. Every position of the first
// failing test, mixed chains and a chain whose result is also stored must
// keep the source answers.

struct Box
{
    x, y, w, h: s32
}

#[Swag.Optimize(true), Swag.NoInline]
func inside(b: const *Box, px, py: s32)->bool => px >= b.x and py >= b.y and px < b.x + b.w and py < b.y + b.h

#[Swag.Optimize(true), Swag.NoInline]
func outside(b: const *Box, px, py: s32)->bool => px < b.x or py < b.y or px >= b.x + b.w or py >= b.y + b.h

#[Swag.Optimize(true), Swag.NoInline]
func mixed(a, b, c, d: u32)->bool => (a < b and b < c) or (c < d and a != 0)

#[Swag.NoInline]
func record(slot: *bool, value: bool)
{
    slot[] = value
}

#[Swag.Optimize(true), Swag.NoInline]
func stored(slot: *bool, a, b, c: s64)->s64
{
    let all = a > 0 and b > 0 and c > 0
    record(slot, all)
    if all do
        return a + b + c
    return -1
}

#test
{
    var b: Box = {x: 10, y: 20, w: 5, h: 6}
    let xs     = [9, 10, 14, 15]
    let ys     = [19, 20, 25, 26]
    for px in xs
    {
        for py in ys
        {
            let wanted = px >= 10 and px < 15 and py >= 20 and py < 26
            Swag.assert(inside(&b, px, py) == wanted)
            Swag.assert(outside(&b, px, py) == not wanted)
        }
    }

    Swag.assert(mixed(1, 2, 3, 0))
    Swag.assert(not mixed(2, 1, 3, 0))
    Swag.assert(mixed(0, 0, 3, 4) == false)
    Swag.assert(mixed(5, 0, 3, 4))

    var slot = false
    Swag.assert(stored(&slot, 1, 2, 3) == 6 and slot)
    Swag.assert(stored(&slot, 1, 0, 3) == -1 and not slot)
    Swag.assert(stored(&slot, 1, 2, -3) == -1 and not slot)
    Swag.assert(stored(&slot, -1, 2, 3) == -1 and not slot)
}
