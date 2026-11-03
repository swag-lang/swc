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
    Swag.require(Swag.kindOf(boxed) == AnyEmptyBoxingJit)
    Swag.require(assume cast(const *AnyEmptyBoxingJit, boxed) != null)
}
