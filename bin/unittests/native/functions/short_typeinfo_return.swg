#global private

func makeArrayInfo() => #typeof(#type [3] u16)
func makeSliceInfo() => #typeof(#type [..] bool?)

#test
{
    let arrayInfo = makeArrayInfo()
    let sliceInfo = makeSliceInfo()
    #assert(#typeof(arrayInfo) == const *TypeInfoArray)
    #assert(#typeof(sliceInfo) == const *TypeInfoSlice)
    Swag.require(arrayInfo.count == 3)
    Swag.require(arrayInfo.totalCount == 3)
    Swag.require(arrayInfo.finalType == u16)
    Swag.require(sliceInfo.pointedType == bool)
}
