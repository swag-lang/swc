#global fileprivate
//#global skip
func N() => 10

#assert(#typeof(N()) == #typeof(10))
#assert(#typeof(#run N()) == #typeof(10))

var arr: [#run N()] s32

#test
{
    @assert(@countof(arr) == 10)
}
