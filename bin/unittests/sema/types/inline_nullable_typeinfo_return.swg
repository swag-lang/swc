#global fileprivate

#[Swag.Inline]
func inlineNullableTypeInfo(value: typeinfo)->#null typeinfo => value

func semaTest001()
{
    let info: typeinfo = s32
    let widenedInfo: #null typeinfo = inlineNullableTypeInfo(info)

    #assert(#typeof(widenedInfo) == #null typeinfo)
    @assert(widenedInfo == s32)
}
