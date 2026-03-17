#global fileprivate
#global skip
//#[Swag.PrintBc]
#test
{
    let arr: const [..] s32 = [1, 2]
    @assert(@countof(arr) == 2)
}
