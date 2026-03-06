// @FAIL
#global skip
#global fileprivate
//#[Swag.PrintBc]
#test
{
    @assert(@countof({1, 2}) == 2)
}
