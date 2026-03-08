#global fileprivate

var a: [2] s32 = [50, 60]

//#[Swag.PrintBc]
#run
{
    @assert(a[0] == 50)
    @assert(a[1] == 60)
}
