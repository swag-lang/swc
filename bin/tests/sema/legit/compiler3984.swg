#global fileprivate // swc-option sema-only
#global skip
func toto()
{
    func titi(f: const &{ a: s32 } = {}) {}

    titi()
}
