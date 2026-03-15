// swc-option suite-test

#global fileprivate
//#[Swag.PrintBc]
func main()->bool
{
    var v:  bool = false
    var p1: *s32 = cast(*s32) &v
    return p1 == cast(*s32) &v
}

#test
{
    @assert(main())
}
