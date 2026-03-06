// @FAIL
#global skip
#global fileprivate
struct Point {}

//#[Swag.PrintBc]
func(T) toto() {}

//#[Swag.PrintBc]
#test
{
    toto'Point()
}
