// swc-option suite-test

#global fileprivate
#global skip
//
//#global testerror

//#[Swag.PrintBc]
func toto(x: ...)
{
    @assert(#typeof(x[0]).fullname == "any")
}

#test
{
    toto(5)
}
