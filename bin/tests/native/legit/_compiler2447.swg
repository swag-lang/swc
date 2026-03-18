#global fileprivate
//#global skip
func N() => 10

#assert(#typeof(N()) == s32)
#assert(#typeof(#run N()) == s32)

var arr: [#run N()] s32

#test
{
    @assert(@countof(arr) == 10)
}
