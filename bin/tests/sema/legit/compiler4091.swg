#global fileprivate
#global skip
#test
{
    if @dbgalloc()
    {
        @dbgalloc().countAlloc = @dbgalloc().countAlloc
        var x = @rtflags
    }
}
