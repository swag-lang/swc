#global fileprivate // swc-option sema-only
#global skip
//#global testerror

//#[Swag.PrintBc]
#test
{
    let a = dref #typeof(s32)
    @assert(a.name == "s32")
}
