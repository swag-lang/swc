#global private

interface INullPatternCast {}
struct NullPatternCast {}
impl INullPatternCast for NullPatternCast {}

#test
{
    let missing: INullPatternCast? = null
    let castResult1 = cast #try (*NullPatternCast) missing
    Swag.assert(castResult1 == null)
    let castResult2 = cast #try (INullPatternCast) missing
    Swag.assert(castResult2 == null)
    let boxed: any? = null
    let castResult3 = cast #try (*s32) boxed
    Swag.assert(castResult3 == null)
}
