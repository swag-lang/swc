#global fileprivate // swc-option sema-only
#global skip
func set(a: u8) { @assert(a == 100) }

#test
{
    set(100)
}
