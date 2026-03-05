#global fileprivate

#[Swag.PrintMicro]
#run
{
    const c: any = 1
    let d = cast(s64) c
    @assert(d == 1)
}
