#global fileprivate // swc-option sema-only
#global skip
interface TOTO
{
    alias FL = func(*TOTO)
    func x(me);
}
