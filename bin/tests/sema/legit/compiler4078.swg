#global fileprivate // swc-option sema-only
#global skip
#test
{
    var dbg: Swag.DebugAllocator
    dbg.printLeaks()
}
