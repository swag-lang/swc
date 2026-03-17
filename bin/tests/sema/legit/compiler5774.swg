#global fileprivate
#global skip
var G: *s32

func toto()->*s32
{
    G = null
    return G
}

//#[Swag.PrintGenBc]
#test
{
    //let ptr = toto()
    //dref ptr = 0
}
