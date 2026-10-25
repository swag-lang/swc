#global private

#[Swag.Inline]
func inlineNullableAssert(value: *s32?)->*s32 => unwrap value

func semaTest001()
{
    var value: *s32?
    let result   = inlineNullableAssert(value)
    let asserted = unwrap value

    #assert(#typeof(result) == *s32)
    #assert(#typeof(asserted) == *s32)
}
