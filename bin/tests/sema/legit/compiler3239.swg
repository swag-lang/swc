#global fileprivate // swc-option sema-only
#global skip
public struct SysCommandEvent3239
{
    enum Kind
    {
        Minimize
        Maximize
        Restore
        Close
    }

    sysKind: Kind = undefined
}
