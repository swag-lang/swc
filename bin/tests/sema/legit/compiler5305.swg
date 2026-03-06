#global fileprivate
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
