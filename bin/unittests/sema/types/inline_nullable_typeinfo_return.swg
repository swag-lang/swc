#global private

#[Swag.Inline]
func inlineNullableTypeInfo(value: typeinfo)->typeinfo? => value

func semaTest001()
{
    let info:        typeinfo  = s32
    let widenedInfo: typeinfo? = inlineNullableTypeInfo(info)

    #assert(#typeof(widenedInfo) == typeinfo?)
    Swag.assert(widenedInfo == s32)
}
