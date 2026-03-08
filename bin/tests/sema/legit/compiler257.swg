#global fileprivate
func test1()->s32 { return 666; }

#run
{
    @assert(test1() == 666)
}
