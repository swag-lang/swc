#global fileprivate
#global skip
func toto()
{
    func titi(f: const &{ a: s32 } = {}) {}

    titi()
}
