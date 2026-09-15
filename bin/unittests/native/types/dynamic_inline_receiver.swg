#global private

struct DynamicInlineImage { pixels: *u8? }

impl DynamicInlineImage
{
    #[Swag.Inline]
    mtd const isValid()->bool => .pixels != null
}

interface IDynamicInlineOwner {}
struct DynamicInlineOwner { image: DynamicInlineImage }
impl IDynamicInlineOwner for DynamicInlineOwner {}

#[Swag.Inline]
func dynamicInlineNull(value: *s32?)->bool => value == null

#test
{
    var owner: DynamicInlineOwner
    let view:  IDynamicInlineOwner = &owner
    Swag.assert(not (cast #assume (*DynamicInlineOwner) view).image.isValid())
}

#test
{
    let absent: *s32? = null
    let boxed:  any?  = absent
    Swag.assert(dynamicInlineNull(cast #assume (*s32?) boxed))
}
