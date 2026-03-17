#global fileprivate // swc-option sema-only
#global skip
#test
{
    #scope(Up)
    for 5
    {
        break to Up
    }
}
