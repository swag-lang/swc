#global private
#global #[Swag.ExplicitNullability]

struct AnyEmptyBoxingNative
{
}

#test
{
    const boxed: #nonull any = AnyEmptyBoxingNative{}
    @assert(@kindof(boxed) == AnyEmptyBoxingNative)
    @assert(cast(#nonull const *AnyEmptyBoxingNative) boxed != null)
}
