#global fileprivate // swc-option sema-only
#global skip
struct AA
{
    x:     s32
    y:     s32
}

#assert(@countof(#typeof(AA).fields) == 2)
