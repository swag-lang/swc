// swc-option suite-test

#global fileprivate
#global skip
//
//#global testerror

//#[Swag.PrintBc]
func toto(x: ...)
{
    @assert(@kindof(x[0]).fullname == "s32")
}

#test
{
    toto(5)
}
