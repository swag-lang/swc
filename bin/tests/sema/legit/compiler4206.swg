#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
func toto(ptr: Swag.IAllocator)->*void
{
    let v = ptr orelse @getcontext().allocator
    return @dataof(v)
}
