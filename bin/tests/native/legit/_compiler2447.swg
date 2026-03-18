#global fileprivate
//#global skip
func N() => 10

#assert(#typeof(N()) == #typeof(10))
#assert(#typeof(#run N()) == #typeof(10))

const ArrCount = cast(s32) #run N()
var arr: [ArrCount] s32

#test
{
    @assert(@countof(arr) == 10)
}
