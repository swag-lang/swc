#global fileprivate
#global skip
//#global testerror

#test
{
    var x = @kindof(@getcontext().allocator)
}
