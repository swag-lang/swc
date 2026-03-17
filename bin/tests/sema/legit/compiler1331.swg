#global fileprivate // swc-option sema-only
#global skip
interface toto
{
    func print(me);
}

#assert(#sizeof(toto) == #sizeof(*void) * 2)
