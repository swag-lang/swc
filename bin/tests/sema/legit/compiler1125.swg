#global fileprivate // swc-option sema-only
#global skip
func titi() {}

func toto()
{
    return titi()
}
