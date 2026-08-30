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
    Swag.assert(Swag.kindOf(boxed) == AnyEmptyBoxingJit)
    Swag.assert(cast(const *AnyEmptyBoxingJit) boxed != null)
}
