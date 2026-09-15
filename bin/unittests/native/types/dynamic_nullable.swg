#global private

// The box itself can be present while its stored pointer is null.
func unboxPresentPointer(value: any)->*s32?
{
    return cast #assume (*s32?) value
}

#[Swag.Safety(.DynCast, true)]
func unboxNullablePointer(value: any?)->*s32?
{
    return cast #assume (*s32?) value
}

#test
{
    let absent: *s32? = null
    Swag.assert(unboxNullablePointer(absent) == null)
    Swag.assert(unboxNullablePointer(null) == null)
    var value: s32 = 42
    Swag.assert(unboxNullablePointer(&value) == &value)
    Swag.assert(unboxPresentPointer(&value) == &value)
}
