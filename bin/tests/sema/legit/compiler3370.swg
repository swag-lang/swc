#global fileprivate // swc-option sema-only
#global skip
#test
{
    const x: [1, 1] s32 = [[1]]
    foreach x
    {
        //@print(@index)
    }
}
