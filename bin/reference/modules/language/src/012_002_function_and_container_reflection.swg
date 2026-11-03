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
    let type       = assume cast(const *Swag.TypeInfoFunc, #typeof(reflectedAdd))
    let parameters = unwrap type.parameters

    Swag.require(parameters.count == 2)
    Swag.require(parameters[0].name == "left")
    Swag.require(parameters[0].pointedType == s32)
    Swag.require(parameters[1].name == "right")
    Swag.require(parameters[1].pointedType == s32)
    Swag.require(type.returnType == s32)

    let noResult = assume cast(const *Swag.TypeInfoFunc, #typeof(reflectedNotify))
    Swag.require(noResult.returnType == null)
}

/**
# Pointer, Array, and Slice Reflection

Container descriptors identify their element type. Arrays additionally expose
their dimensions; pointer and slice descriptors expose the pointed-to type.
*/

#test
{
    let pointer = assume cast(const *Swag.TypeInfoPointer, #type *s32)
    Swag.require(pointer.kind == .Pointer)
    Swag.require(pointer.pointedType == s32)

    let array = assume cast(const *Swag.TypeInfoArray, #type [2, 3] u16)
    Swag.require(array.kind == .Array)
    Swag.require(array.pointedType == #type [3] u16)
    Swag.require(array.finalType == u16)
    Swag.require(array.count == 2)
    Swag.require(array.totalCount == 6)

    let slice = assume cast(const *Swag.TypeInfoSlice, #type [..] f32)
    Swag.require(slice.kind == .Slice)
    Swag.require(slice.pointedType == f32)
}
