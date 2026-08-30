#global private
using Swag

func selectTypeInfo(flag: bool)->typeinfo
{
    return flag ? #type const [2] f32 : #type func()->s32
}

#test
{
    let arrayInfo = selectTypeInfo(true)
    let funcInfo  = selectTypeInfo(false)
    #assert(#typeof(arrayInfo) == typeinfo)
    #assert(#typeof(funcInfo) == typeinfo)
    Swag.assert(arrayInfo == #type const [2] f32)
    Swag.assert(funcInfo == #type func()->s32)
    Swag.assert((cast(const *TypeInfoFunc) funcInfo).returnType == s32)
}
