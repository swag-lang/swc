#global fileprivate
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
