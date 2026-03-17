#global fileprivate // swc-option sema-only
#global skip
#global skip
func C(value: const& bool)
{
    if value
    {

    }
}

#test
{
    C(true)
}
