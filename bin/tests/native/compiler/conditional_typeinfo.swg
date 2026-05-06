#global fileprivate
using Swag

func selectTypeInfo(flag: bool)->typeinfo
{
    return flag ? #type const [2] f32 : #type func()->s32
}

#test
{
    let arrayInfo = selectTypeInfo(true)
    let funcInfo = selectTypeInfo(false)
    #assert(#typeof(arrayInfo) == typeinfo)
    #assert(#typeof(funcInfo) == typeinfo)
    @assert(arrayInfo == #type const [2] f32)
    @assert(funcInfo == #type func()->s32)
    @assert((cast(const *TypeInfoFunc) funcInfo).returnType == s32)
}
