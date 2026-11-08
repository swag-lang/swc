#global public

using Swag

struct Carrier
{
    public late borrowed: *s32
    public late owned:    *s32
}

#[Swag.NoInline]
func create(borrowed: *s32)->*Carrier
{
    let carrier = cast(*Carrier, allocate(#sizeof(Carrier)))
    carrier.borrowed = borrowed
    carrier.owned = cast(*s32, allocate(#sizeof(s32)))
    return carrier
}

#[Swag.NoInline]
func createWrapped(borrowed: *s32)->*Carrier => create(borrowed)
