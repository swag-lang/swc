#global fileprivate // swc-option sema-only
#global skip
/*struct(T: [..] typeinfo) AA
{
}*/

#test
{
    const X = s32
    @assert(X == s32)
}
