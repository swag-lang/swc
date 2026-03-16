#global fileprivate // swc-option suite-test

const TypedValue: s32 = 10

#assert(#typeof(TypedValue) == s32)
#assert(#typeof(10) == s8)
#assert(#typeof(-10) == s8)
#assert(#typeof(0xFF) == u8)
#assert(#typeof(0x1_0000) == u32)
#assert(#typeof(1.0) == f32)
#assert(#typeof(1.0'f64) == f64)
#assert(#typeof(10'u8 + 20'u16) == u16)
#assert(#typeof(10'u8 + 20's16) == s16)
#assert(#typeof(10's16 + 20's64) == s64)
#assert(#typeof(1 + 1'u32) == u32)
#assert(#typeof(1 + 1's64) == s64)
#assert(#typeof(cast(*u8) null) == *u8)
#assert(#typeof(true) == bool)
#assert(#typeof("x") == string)
#assert(#typeof(func()->s32) == #type func()->s32)

struct TypeOfPair { left, right: s16 }

const TYPEOF_ARRAY = cast(const *Swag.TypeInfoArray) #typeof(#type [2, 3] TypeOfPair)
#assert(#typeof(#type [2, 3] TypeOfPair) == #type [2, 3] TypeOfPair)
#assert(TYPEOF_ARRAY.count == 2)
#assert(TYPEOF_ARRAY.totalCount == 6)
#assert(TYPEOF_ARRAY.pointedType == #type [3] TypeOfPair)
#assert(TYPEOF_ARRAY.finalType == TypeOfPair)

const TYPEOF_SLICE = cast(const *Swag.TypeInfoSlice) #typeof(#type [..] TypeOfPair)
#assert(#typeof(#type [..] TypeOfPair) == #type [..] TypeOfPair)
#assert(TYPEOF_SLICE.pointedType == TypeOfPair)

const TYPEOF_FUNC = cast(const *Swag.TypeInfoFunc) #typeof(#type func(s32)->bool)
#assert(#typeof(#type func(s32)->bool) == #type func(s32)->bool)
#assert(@countof(TYPEOF_FUNC.parameters) == 1)
#assert(TYPEOF_FUNC.parameters[0].pointedType == s32)
#assert(TYPEOF_FUNC.returnType == bool)

#test
{
    var local = 1 + 1'u16
    var ptr = cast(*u8) null

    #assert(#typeof(local) == u16)
    #assert(#typeof(ptr) == *u8)

    @assert(local == 2'u16)
    @assert(ptr == null)
}

// @BUG native constant-relocation validation fails for local arrays of nested typeinfo values.
// #test
// {
//     var types: [?] typeinfo = [#typeof(#type [2, 3] TypeOfPair), #typeof(#type [..] TypeOfPair)]
//
//     let arrayInfo = cast(const *Swag.TypeInfoArray) types[0]
//     let sliceInfo = cast(const *Swag.TypeInfoSlice) types[1]
//
//     @assert(types[0] == #type [2, 3] TypeOfPair)
//     @assert(types[1] == #type [..] TypeOfPair)
//     @assert(arrayInfo.totalCount == 6)
//     @assert(arrayInfo.finalType == TypeOfPair)
//     @assert(sliceInfo.pointedType == TypeOfPair)
// }
