#global fileprivate

struct AnyEmptyBoxingNative
{
}

#test
{
    const boxed: any = AnyEmptyBoxingNative{}
    @assert(@kindof(boxed) == AnyEmptyBoxingNative)
    @assert(cast(const *AnyEmptyBoxingNative) boxed != null)
}
