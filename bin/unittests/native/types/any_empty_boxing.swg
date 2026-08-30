#global private

struct AnyEmptyBoxingNative {}

#test
{
    const boxed: any = AnyEmptyBoxingNative{}
    Swag.assert(Swag.kindOf(boxed) == AnyEmptyBoxingNative)
    Swag.assert(cast(const *AnyEmptyBoxingNative) boxed != null)
}
