#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    func toto(cb: func||() = null)
    {
        @assert(cb == null)
        if cb do
            cb()
    }

    toto()
}
