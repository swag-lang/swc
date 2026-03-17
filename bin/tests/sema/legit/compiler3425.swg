#global fileprivate // swc-option sema-only
#global skip
#test
{
    var str = "10"
    var v:  func||() = func||()
    {
        //@print(str)
    }

    //v()
}
