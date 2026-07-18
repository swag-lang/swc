#global private
#global #[Swag.ExplicitNullability]

enum AnyKind
{
    A = 1,
    B = 4
}

func anyToEnum()->bool
{
    var boxed: #nonull any = AnyKind.B
    let value = cast(AnyKind) boxed
    return value == AnyKind.B
}

func anyToPointer()->bool
{
    var value: s32 = 77
    var boxed: #nonull any = &value
    let ptr = cast(#nonull *s32) boxed
    return ptr == &value and dref ptr == 77
}

func anyToSlice()->bool
{
    var data: [4] s32 = [3, 6, 9, 12]
    let src = cast(#nonull [..] s32) data
    var boxed: #nonull any = src
    let dst = cast(#nonull [..] s32) boxed
    return @countof(dst) == 4 and dst[0] == 3 and dst[2] == 9 and dst[3] == 12
}

#test
{
    @assert(anyToEnum())
    @assert(anyToPointer())
    @assert(anyToSlice())
}
