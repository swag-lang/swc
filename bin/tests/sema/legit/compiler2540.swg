#global fileprivate
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
