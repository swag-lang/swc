#global fileprivate // swc-option sema-only
#global skip
#test
{
    func toto(cb: func||())
    {
        @assert(cb == null)
        if cb do
            cb()
    }

    toto(null)
}
