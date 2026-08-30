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
    let parameters = type.parameters!

    Swag.assert(parameters.count == 2)
    Swag.assert(parameters[0].name == "left")
    Swag.assert(parameters[0].pointedType == s32)
    Swag.assert(parameters[1].name == "right")
    Swag.assert(parameters[1].pointedType == s32)
    Swag.assert(type.returnType == s32)

    let noResult = cast(const *Swag.TypeInfoFunc) #typeof(reflectedNotify)
    Swag.assert(noResult.returnType == null)
}

/**
# Pointer, Array, and Slice Reflection

Container descriptors identify their element type. Arrays additionally expose
their dimensions; pointer and slice descriptors expose the pointed-to type.
*/

#test
{
    let pointer = cast(const *Swag.TypeInfoPointer) #type *s32
    Swag.assert(pointer.kind == .Pointer)
    Swag.assert(pointer.pointedType == s32)

    let array = cast(const *Swag.TypeInfoArray) #type [2, 3] u16
    Swag.assert(array.kind == .Array)
    Swag.assert(array.pointedType == #type [3] u16)
    Swag.assert(array.finalType == u16)
    Swag.assert(array.count == 2)
    Swag.assert(array.totalCount == 6)

    let slice = cast(const *Swag.TypeInfoSlice) #type [..] f32
    Swag.assert(slice.kind == .Slice)
    Swag.assert(slice.pointedType == f32)
}
