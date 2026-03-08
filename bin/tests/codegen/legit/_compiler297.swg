#global fileprivate

//#[Swag.PrintBc]
func test1()->string
{
    return "toto1"
}

#run
{
    let c = test1()
    @assert(c == "toto1")
}
