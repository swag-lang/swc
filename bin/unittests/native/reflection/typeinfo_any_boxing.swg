#global private

struct BoxedTypeInfoPair
{
    left:  s32
    right: s32
}

#test
{
    func boxStructTypeInfoInAny()->bool
    {
        let box: any = #typeof(BoxedTypeInfoPair)
        let unboxed = cast(typeinfo) box
        return unboxed == #type BoxedTypeInfoPair and
               unboxed.kind == TypeInfoKind.Struct and
               unboxed.name == "BoxedTypeInfoPair"
    }

    @assert(boxStructTypeInfoInAny())
}
