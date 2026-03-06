#global fileprivate
#global skip
func(op: string) toto()
{
    //@print("coucou")
}

#test
{
    toto'("op")()
}
