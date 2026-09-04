#global private

func makeArrayInfo() => #typeof(#type [3] u16)
func makeSliceInfo() => #typeof(#type [..] bool?)

#test
{
    let arrayInfo = makeArrayInfo()
    let sliceInfo = makeSliceInfo()
    #assert(#typeof(arrayInfo) == const *TypeInfoArray)
    #assert(#typeof(sliceInfo) == const *TypeInfoSlice)
    Swag.assert(arrayInfo.count == 3)
    Swag.assert(arrayInfo.totalCount == 3)
    Swag.assert(arrayInfo.finalType == u16)
    Swag.assert(sliceInfo.pointedType == bool)
}
