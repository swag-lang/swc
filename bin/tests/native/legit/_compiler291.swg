// swc-option suite-test

#global fileprivate
using Swag

//#[PrintBc]
func test2(v: string, v1: string)->bool
{
    //@print(v);
    //@print(v1);
    return v == "toto" and v1 == "titi"
}

//#[PrintBc]
#test
{
    @assert(test2("toto", "titi"))
}
