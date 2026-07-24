#global private

/**
# Function Reflection

'#typeof' on a function yields 'Swag.TypeInfoFunc'. Its parameter entries are
'TypeValue' records, and 'returnType' is 'null' for a function with no return
value.
*/

func reflectedAdd(left: s32, right: s32)->s32
{
    return left + right
}

func reflectedNotify(value: bool)
{
    discard value
}

#test
{
    let type       = cast(const *Swag.TypeInfoFunc) #typeof(reflectedAdd)
    let parameters = notnull type.parameters

    @assert(@countof(parameters) == 2)
    @assert(parameters[0].name == "left")
    @assert(parameters[0].pointedType == s32)
    @assert(parameters[1].name == "right")
    @assert(parameters[1].pointedType == s32)
    @assert(type.returnType == s32)

    let noResult = cast(const *Swag.TypeInfoFunc) #typeof(reflectedNotify)
    @assert(noResult.returnType == null)
}

/**
# Pointer, Array, and Slice Reflection

Container descriptors identify their element type. Arrays additionally expose
their dimensions; pointer and slice descriptors expose the pointed-to type.
*/

#test
{
    let pointer = cast(const *Swag.TypeInfoPointer) #type *s32
    @assert(pointer.kind == .Pointer)
    @assert(pointer.pointedType == s32)

    let array = cast(const *Swag.TypeInfoArray) #type [2, 3] u16
    @assert(array.kind == .Array)
    @assert(array.pointedType == #type [3] u16)
    @assert(array.finalType == u16)
    @assert(array.count == 2)
    @assert(array.totalCount == 6)

    let slice = cast(const *Swag.TypeInfoSlice) #type [..] f32
    @assert(slice.kind == .Slice)
    @assert(slice.pointedType == f32)
}
