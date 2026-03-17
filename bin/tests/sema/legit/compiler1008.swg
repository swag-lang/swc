#global fileprivate
#global skip
using Swag

//#[Swag.PrintBc]
#test
{
    let x: any = 6
    @assert(cast(s32) x == 6)
}
