// swc-option suite-test

#global fileprivate
#global skip
//
//#global testerror

//#[Swag.PrintBc]
func toto(x: ...)->typeinfo
{
    @assert(@kindof(x[0]).fullname == "s32")
    return @kindof(x[0])
}

#test
{
    @assert(toto(5) == s32)
}
