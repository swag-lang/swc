#global private
#global #[Swag.ExplicitNullability]

#[Swag.Inline]
func inlineNullableTypeInfo(value: #nonull typeinfo)->#null typeinfo => value

func semaTest001()
{
    let info: #nonull typeinfo = s32
    let widenedInfo: #null typeinfo = inlineNullableTypeInfo(info)

    #assert(#typeof(widenedInfo) == #null typeinfo)
    @assert(widenedInfo == s32)
}
