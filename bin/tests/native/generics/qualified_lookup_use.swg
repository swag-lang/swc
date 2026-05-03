#global fileprivate

#test
{
    let value = QualifiedGenericCrossFile.useLater(41)
    #assert(#typeof(value) == s32)
    @assert(value == 42)
}
