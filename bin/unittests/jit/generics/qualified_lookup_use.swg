#global private

#test
{
    let value = QualifiedGenericCrossFile.useLater(41)
    #assert(#typeof(value) == s32)
    Swag.require(value == 42)
}
