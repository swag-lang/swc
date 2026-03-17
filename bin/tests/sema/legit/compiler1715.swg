#global fileprivate // swc-option sema-only
#global skip
#test
{
    func toto(x: func(string))
    {
        x("64")
    }

    toto(func(x) { @assert(x == "64"); })
}
