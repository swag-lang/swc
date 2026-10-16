#global public

#[Swag.NoInline]
func depReleaseBox(box: *(*s32?))
{
    if let item = box[]
    {
        var request: Swag.AllocatorRequest
        request.address = item
        request.size    = #sizeof(s32)
        Swag.getContext().allocator!.free(&request)
        box[] = null
    }
}

#[Swag.NoInline]
func depReleaseBoxWrapper(box: *(*s32?)) => depReleaseBox(box)

#[Swag.NoInline]
func depReleaseBoxOuter(box: *(*s32?)) => depReleaseBoxWrapper(box)

#[Swag.NoInline]
func depReleaseSecondBox(_: *(*s32?), box: *(*s32?)) => depReleaseBoxOuter(box)
