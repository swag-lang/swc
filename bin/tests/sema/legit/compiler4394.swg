#global fileprivate // swc-option sema-only
#global skip
struct(T: const [2] s32) A {}
struct(T) B {}

#test
{
    var x: A'([2, 2])
    var b: B'(#type [2] s32)
}
