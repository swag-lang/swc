#global private

func makeArrayInfo() => #typeof(#type [3] u16)
func makeSliceInfo() => #typeof(#type #null [..] bool)

#test
{
    let arrayInfo = makeArrayInfo()
    let sliceInfo = makeSliceInfo()
    #assert(#typeof(arrayInfo) == const *TypeInfoArray)
    #assert(#typeof(sliceInfo) == const *TypeInfoSlice)
    @assert(arrayInfo.count == 3)
    @assert(arrayInfo.totalCount == 3)
    @assert(arrayInfo.finalType == u16)
    @assert(sliceInfo.pointedType == bool)
}
