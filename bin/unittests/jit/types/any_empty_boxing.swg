#global private

struct AnyEmptyBoxingJit {}

func makeAnyEmptyBoxingJit(flag: bool)->AnyEmptyBoxingJit
{
    if flag do
        return AnyEmptyBoxingJit{}
    return AnyEmptyBoxingJit{}
}

#test
{
    let boxed: any = makeAnyEmptyBoxingJit(false)
    @assert(@kindof(boxed) == AnyEmptyBoxingJit)
    @assert(cast(const *AnyEmptyBoxingJit) boxed != null)
}
