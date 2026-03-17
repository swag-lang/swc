#global fileprivate // swc-option sema-only
#global skip
//#global testerror

#test
{
    var x = @kindof(@getcontext().allocator)
}
