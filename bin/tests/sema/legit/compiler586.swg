// @FAIL
#global skip
#global fileprivate
func(op: string) toto()
{
    //@print("coucou")
}

#test
{
    toto'("op")()
}
