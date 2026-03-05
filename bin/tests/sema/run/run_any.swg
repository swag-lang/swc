#global fileprivate

#run
{
    let b = 1
    let c: any = b
    let d = cast(s64) c
    @assert(d == 1)
}
