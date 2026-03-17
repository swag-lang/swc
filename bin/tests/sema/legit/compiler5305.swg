#global fileprivate // swc-option sema-only
#global skip
func titi() throw
{
}

func toto()
{
    assume
    {
        titi()
    }
}

#test
{
    toto()
}
