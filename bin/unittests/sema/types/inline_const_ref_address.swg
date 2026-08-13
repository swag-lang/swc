#global private

#[Swag.Inline]
func inlineConstRefAddress(value: s32)
{
    #assert(#typeof(value) == s32)
}

func semaTest001()
{
    var value: s32 = 41
    inlineConstRefAddress(value)
}
