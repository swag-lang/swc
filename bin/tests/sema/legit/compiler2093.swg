#global fileprivate // swc-option sema-only
#global skip
func(T) AA() {}

//#[Swag.PrintBc]
#test
{
    alias RR = AA's32
    RR()
    //@assert(#typeof(x.v) == s64)
}
