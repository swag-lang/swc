#global fileprivate // swc-option sema-only
#global skip
func toto(f: f32)
    where
    {
        return true
    }
{
}

#test
{
    toto(0)
}
