#global fileprivate // swc-option sema-only
#global skip
func toto() {}

func toto1() => toto()

#test
{
}
