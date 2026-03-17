#global fileprivate // swc-option sema-only
#global skip
struct AA
{
    b:   AAPtr
}

alias AAPtr = *AA
