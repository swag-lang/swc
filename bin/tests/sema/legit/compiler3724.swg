#global fileprivate // swc-option sema-only
#global skip
attr toto(x: s32)

#test
{
    var x = #typeof(toto)
}
