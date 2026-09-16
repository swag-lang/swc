#global private

interface INullPatternCast {}
struct NullPatternCast {}
impl INullPatternCast for NullPatternCast {}

#test
{
    let missing: INullPatternCast? = null
    Swag.assert(cast #try (*NullPatternCast) missing == null)
    Swag.assert(cast #try (INullPatternCast) missing == null)
    let boxed: any? = null
    Swag.assert(cast #try (*s32) boxed == null)
}
