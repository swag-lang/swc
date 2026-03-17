#global fileprivate // swc-option sema-only
#global skip
alias GG = s32
enum AA: GG
{
    A = 0
    B
}

#assert(AA.B == 1)
