#global private

struct AnyEmptyBoxingNative {}

#test
{
    const boxed: any = AnyEmptyBoxingNative{}
    Swag.require(Swag.kindOf(boxed) == AnyEmptyBoxingNative)
    Swag.require(assume cast(const *AnyEmptyBoxingNative, boxed) != null)
}
