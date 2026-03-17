#global fileprivate // swc-option sema-only
#global skip
#test
{
    if @dbgalloc()
    {
        @dbgalloc().countAlloc = @dbgalloc().countAlloc
        var x = @rtflags
    }
}
