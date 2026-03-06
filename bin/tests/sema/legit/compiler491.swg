// @FAIL
#global skip
#global fileprivate
//#[Swag.PrintBc]
#test
{
    var res = {"true", "false"}
    @assert(res.item0 == "true")
    @assert(res.item1 == "false")
}
