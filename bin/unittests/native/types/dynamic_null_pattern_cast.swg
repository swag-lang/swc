#global private

interface INullPatternCast {}
struct NullPatternCast {}
impl INullPatternCast for NullPatternCast {}

#test
{
    let missing: INullPatternCast? = null
    let castResult1 = catch cast(*NullPatternCast?, missing)
    Swag.require(castResult1 == null)
    let castResult2 = cast(INullPatternCast?, missing)
    Swag.require(castResult2 == null)
    let boxed: any? = null
    let castResult3 = catch cast(*s32?, boxed)
    Swag.require(castResult3 == null)
}
