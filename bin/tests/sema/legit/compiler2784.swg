#global fileprivate // swc-option sema-only
#global skip
struct AA {}

var G = false
func toto(x: AA)
{
    G = true
}

//#[Swag.PrintBc]
#test
{
    let x   = &toto
    var tt: AA
    tt.x()
}
