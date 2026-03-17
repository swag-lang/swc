#global fileprivate // swc-option sema-only
#global skip
func(op: string) toto()
{
    //@print("coucou")
}

#test
{
    toto'("op")()
}
