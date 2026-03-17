#global fileprivate // swc-option sema-only
#global skip
#test
{
    let a = 0
    switch
    {
    case a:
        break
    }
}
