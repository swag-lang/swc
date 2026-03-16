#global fileprivate // swc-option suite-test
#global skip // @BUG native enum/array/slice reflection payloads assert or materialize empty in native

enum ReflectMode: s16
{
    First = -2
    Second = 7
    Third = 9
}

const ENUM_INFO = cast(const *Swag.TypeInfoEnum) #typeof(ReflectMode)
#assert(#typeof(ReflectMode).kind == .Enum)
#assert(ENUM_INFO.rawType == s16)
#assert(@countof(ENUM_INFO.values) == 3)
#assert(ENUM_INFO.values[0].name == "First")
#assert(ENUM_INFO.values[1].name == "Second")
#assert(ENUM_INFO.values[2].name == "Third")

const FIRST_VALUE = cast(const *ReflectMode) ENUM_INFO.values[0].value
const SECOND_VALUE = cast(const *ReflectMode) ENUM_INFO.values[1].value
#assert(cast(s16) dref FIRST_VALUE == -2's16)
#assert(cast(s16) dref SECOND_VALUE == 7's16)

const ARRAY_INFO0 = cast(const *Swag.TypeInfoArray) #typeof(#type [2] s32)
#assert(#typeof(#type [2] s32).kind == .Array)
#assert(ARRAY_INFO0.count == 2)
#assert(ARRAY_INFO0.totalCount == 2)
#assert(ARRAY_INFO0.pointedType == s32)
#assert(ARRAY_INFO0.finalType == s32)

const ARRAY_INFO1 = cast(const *Swag.TypeInfoArray) #typeof(#type [2, 3] ReflectMode)
#assert(ARRAY_INFO1.count == 2)
#assert(ARRAY_INFO1.totalCount == 6)
#assert(ARRAY_INFO1.pointedType == #type [3] ReflectMode)
#assert(ARRAY_INFO1.finalType == ReflectMode)

const SLICE_INFO = cast(const *Swag.TypeInfoSlice) #typeof(#type [..] ReflectMode)
#assert(#typeof(#type [..] ReflectMode).kind == .Slice)
#assert(SLICE_INFO.pointedType == ReflectMode)

#test
{
    let enumInfo = cast(const *Swag.TypeInfoEnum) #typeof(ReflectMode)
    let second = cast(const *ReflectMode) enumInfo.values[1].value
    let arrayInfo = cast(const *Swag.TypeInfoArray) #typeof(#type [2, 3] ReflectMode)
    let sliceInfo = cast(const *Swag.TypeInfoSlice) #typeof(#type [..] ReflectMode)

    @assert(enumInfo.rawType == s16)
    @assert(cast(s16) dref second == 7)
    @assert(arrayInfo.count == 2)
    @assert(arrayInfo.totalCount == 6)
    @assert(arrayInfo.finalType == ReflectMode)
    @assert(sliceInfo.pointedType == ReflectMode)
}
