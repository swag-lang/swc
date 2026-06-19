#global fileprivate

#test
{
    func boxArrayTypeInfoInAny()->bool
    {
        let info = #typeof([1, 2.5])
        let box: any = info
        let unboxed = cast(typeinfo) box
        return unboxed == #type const [2] f32 and
               unboxed.kind == TypeInfoKind.Array and
               unboxed.name == "const [2] f32"
    }

    @assert(boxArrayTypeInfoInAny())
}
