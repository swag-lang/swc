#global private

// A short-circuit chain returned as a bool sends the exits its branches pin
// to one block that sets the constant, and only the last link materializes
// its test. `and` and `or` chains, mixed ones and chains over loaded fields
// must answer as the unoptimized ones do.

struct Box
{
    x, y, w, h: s32
}

#[Swag.Optimize(true), Swag.NoInline]
func inside(b: const *Box, px, py: s32)->bool => px >= b.x and py >= b.y and px < b.x + b.w and py < b.y + b.h
#[Swag.Optimize(false), Swag.NoInline]
func insideRef(b: const *Box, px, py: s32)->bool => px >= b.x and py >= b.y and px < b.x + b.w and py < b.y + b.h

#[Swag.Optimize(true), Swag.NoInline]
func anyEdge(a, b, c, d: s64)->bool => a == 0 or b < 0 or c > d or d == 7
#[Swag.Optimize(false), Swag.NoInline]
func anyEdgeRef(a, b, c, d: s64)->bool => a == 0 or b < 0 or c > d or d == 7

#[Swag.Optimize(true), Swag.NoInline]
func mixed(a, b, c: u32)->bool => (a < b and b < c) or c == 0
#[Swag.Optimize(false), Swag.NoInline]
func mixedRef(a, b, c: u32)->bool => (a < b and b < c) or c == 0

#test
{
    let box = Box{1, 2, 3, 4}
    for px in -2 to 6
    {
        for py in -1 to 8 do
            Swag.assert(inside(&box, px, py) == insideRef(&box, px, py))
    }

    let values = [0's64, 1, -1, 7, 8, -7]
    for a in values
    {
        for b in values
        {
            for c in values
            {
                for d in values do
                    Swag.assert(anyEdge(a, b, c, d) == anyEdgeRef(a, b, c, d))
                let ua = cast #bit (u32) cast #wrap (s32) a
                let ub = cast #bit (u32) cast #wrap (s32) b
                let uc = cast #bit (u32) cast #wrap (s32) c
                Swag.assert(mixed(ua, ub, uc) == mixedRef(ua, ub, uc))
            }
        }
    }
}
