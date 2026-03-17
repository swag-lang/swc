#global fileprivate // 

enum AnyKind
{
    A = 1,
    B = 4
}

func anyToEnum()->bool
{
    var boxed: any = AnyKind.B
    let value = cast(AnyKind) boxed
    return value == AnyKind.B
}

func anyToPointer()->bool
{
    var value: s32 = 77
    var boxed: any = &value
    let ptr = cast(*s32) boxed
    return ptr == &value and dref ptr == 77
}

func anyToSlice()->bool
{
    var data: [4] s32 = [3, 6, 9, 12]
    let src = cast([..] s32) data
    var boxed: any = src
    let dst = cast([..] s32) boxed
    return @countof(dst) == 4 and dst[0] == 3 and dst[2] == 9 and dst[3] == 12
}

#test
{
    @assert(anyToEnum())
    @assert(anyToPointer())
    @assert(anyToSlice())
}
