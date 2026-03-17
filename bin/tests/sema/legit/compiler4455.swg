#global fileprivate // swc-option sema-only
#global skip
//#global testerror
//#[Swag.PrintBc]
#test
{
    {
        var x: [2, 2] string = "true"
        @assert(x[0, 0] == "true")
        @assert(x[1, 0] == "true")
        @assert(x[0, 1] == "true")
        @assert(x[1, 1] == "true")
    }
}
