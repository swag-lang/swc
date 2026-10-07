#global public

// Type notifications prepare method metadata. An unresolved inferred return type must
// reach cycle detection even while that notification is waiting for its descriptor.
#message(Swag.CompilerMsgMask.SemTypes) {}

struct MessageCyclePicture {}
struct MessageCycleSize { width: s32 }

impl MessageCyclePicture
{
    mtd crop(width: s32) { discard width }
    mtd crop(size: MessageCycleSize) => .crop(size.width)     // swc-expected-error {{sema_err_cyclic_dependency}}
}

#test
{
    var picture: MessageCyclePicture
    picture.crop(MessageCycleSize{4})
}
