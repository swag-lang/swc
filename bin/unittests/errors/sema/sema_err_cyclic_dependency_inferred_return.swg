#global public

// A '=>' body with no declared return type calls an overload of its own name: resolving that
// call needs the whole overload set, including the function still being typed. The report
// carries a note saying that an explicit return type breaks the cycle.
struct CyclePicture
{
    width:  s32
    height: s32
}

struct CycleSize
{
    w: s32
    h: s32
}

impl CyclePicture
{
    mtd crop(width, height: s32)
    {
        .width  = width
        .height = height
    }

    mtd crop(size: CycleSize) => .crop(size.w, size.h)     // swc-expected-error {{sema_err_cyclic_dependency}}
}

#test
{
    var picture: CyclePicture
    picture.crop(CycleSize{4, 3})     // swc-expected-error {{sema_err_cannot_cast}}
}
