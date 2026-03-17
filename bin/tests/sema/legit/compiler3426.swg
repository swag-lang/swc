#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintGenBc]
#test
{
    let str = "10"
    let v:  func||() = func|str|()
    {
        @assert(str == "10")
    }

    v()
}
