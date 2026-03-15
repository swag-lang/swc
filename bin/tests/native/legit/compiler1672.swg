// swc-option suite-test

#global fileprivate
#global skip
//
//#global testerror

//#[Swag.PrintBc]
func toto(x: ...)->typeinfo
{
    @assert(#typeof(x[0]).fullname == "any")
    return #typeof(x[0])
}

#test
{
    @assert(toto(5).fullname == "any")
}
