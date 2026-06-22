#global fileprivate

#[Swag.Inline]
func inlineMultiplyWithNarrowedLiteral(value: f32)->f32
{
    return value * 1.4247691104677813
}

#test
{
    const V = #run inlineMultiplyWithNarrowedLiteral(2.0'f32)
    #assert(#typeof(V) == f32)
    #assert(V == 2.0'f32 * 1.4247691104677813'f32)
}
