#global private

#[Swag.Inline]
func inlineAddressReturnedReference(value: &s32)->&s32
{
    return &value
}

#test
{
    var value = 77
    let rp = &inlineAddressReturnedReference(&value)
    #assert(#typeof(rp) == *s32)
    @assert(rp == &value)
}
