#global fileprivate // swc-option sema-only
#global skip
struct(T = s32) A {}

#test
{
    //var x: A
    var y = A{}
}
