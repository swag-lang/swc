// 

#global fileprivate

//#[Swag.PrintBc]
func test1()->string
{
    return "toto1"
}

#test
{
    let c = test1()
    @assert(c == "toto1")
}
