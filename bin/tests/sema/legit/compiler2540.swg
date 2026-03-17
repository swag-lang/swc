#global fileprivate // swc-option sema-only
#global skip
//#[Swag.NoCopy]
struct AA {}

struct BB
{
    x:   AA
}

#test
{
    var x: BB
    var y  = x
}
