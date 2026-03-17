#global fileprivate // swc-option sema-only
#global skip
#[Swag.Inline]
public func toto3462()
{
    func titi(f: func||(s32)) {}

    titi(func||(x: s32) {})
}
