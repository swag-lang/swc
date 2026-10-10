#global private

#[Swag.Inline]
func inlineNullableAssert(value: *s32?)->*s32 => value!

func semaTest001()
{
    var value: *s32?
    let result = inlineNullableAssert(value)
    let asserted = value!

    #assert(#typeof(result) == *s32)
    #assert(#typeof(asserted) == *s32)
}
