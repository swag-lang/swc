#global fileprivate // swc-option sema-only
#global skip
#test
{
    var pt: *void
    if pt
    {
    }

    #[Swag.Strict]
    alias PVOID = *void
    var pt1: PVOID
    if pt1
    {
    }
}
