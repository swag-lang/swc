#global private
#global #[Swag.ExplicitNullability]

#[Swag.Inline]
func inlineConstRefAddress(value: const &s32)
{
    let ptr = &value
    #assert(#typeof(ptr) == const *s32)
}

func semaTest001()
{
    var value: s32 = 41
    inlineConstRefAddress(value)
    inlineConstRefAddress(4)
    inlineConstRefAddress(value + 1)
}
