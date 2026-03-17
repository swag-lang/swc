#global fileprivate // swc-option sema-only
#global skip
#test
{
    func toto(x: func(bool, string))
    {
        x(true, "64")
    }

    toto(func(x, y) { @assert(y == "64"); })
}
