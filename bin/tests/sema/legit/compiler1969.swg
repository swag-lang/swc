#global fileprivate // swc-option sema-only
#global skip
func(T) toto(value: const [..] T) {}

#test
{
    toto'u8(cast(const [..] u8) "string")
}
