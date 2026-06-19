#global fileprivate
using Swag

func selectArrayInfo(flag: bool)->const *TypeInfoArray
{
    let info = flag ? #type const [2] f32 : #type const [2] s32
    #assert(#typeof(info) == const *TypeInfoArray)
    return cast(const *TypeInfoArray) info
}

#test
{
    let trueInfo = selectArrayInfo(true)
    let falseInfo = selectArrayInfo(false)
    @assert(trueInfo.count == 2)
    @assert(trueInfo.finalType == f32)
    @assert(falseInfo.count == 2)
    @assert(falseInfo.finalType == s32)
}
