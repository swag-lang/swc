//

#global fileprivate

//
//#global testerror

//#[Swag.PrintBc]
func toto(x: ...)->typeinfo
{
    @assert(@kindof(x[0]) == s32)
    return @kindof(x[0])
}

#test
{
    @assert(toto(5) == s32)
}
