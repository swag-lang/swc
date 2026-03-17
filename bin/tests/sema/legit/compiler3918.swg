#global fileprivate // swc-option sema-only
#global skip
func toto(x: const *void) {}
func titi() {}

#test
{
    toto(cast() &titi)
}
