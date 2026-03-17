#global fileprivate
#global skip
namespace toto
{
    struct point
    {
        x:     s32 = 10
        y:     s32
    }
}

//#[Swag.PrintBc]
#test
{
    var pt: toto.point
    @assert(pt.x == 10)
}
