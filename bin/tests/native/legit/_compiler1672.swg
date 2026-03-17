// 

#global fileprivate
 
//
//#global testerror

//#[Swag.PrintBc]
func toto(x: ...)->typeinfo
{
    return #typeof(x[0])
}

#test
{
    @assert(toto(5) == any)
}
