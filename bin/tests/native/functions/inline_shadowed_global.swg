#global fileprivate
using Swag

// Inline expansion must stop re-expanding the same function when an inline call graph loops back
// through another inline helper.
struct Angle
{
    rad: s32
}

#[Swag.Inline]
func toDegreesImpl(value: s32)->s32
{
    if !value do
        return 0
    return Angle{rad: value - 1}.toDegrees() + 2
}

impl Angle
{
    #[Swag.Inline]
    mtd const toDegrees()->s32
    {
        if !me.rad do
            return 0
        return toDegreesImpl(me.rad)
    }
}

#test
{
    let angle = Angle{rad: 4}
    @assert(angle.toDegrees() == 8)
}
