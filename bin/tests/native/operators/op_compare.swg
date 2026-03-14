#global fileprivate // swc-option suite-test


#test
{
    var a: *s32 = null
    let b = a == null
    let c = a != null
    #assert(#typeof(b) == bool)
    #assert(#typeof(c) == bool)
}



