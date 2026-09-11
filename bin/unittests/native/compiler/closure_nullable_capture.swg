#global private

func readNullableCapture(value: *s32?)->s32
{
    let read = func|value|()->s32
    {
        if value != null do
            return value[]
        return -1
    }
    return read()
}

func readNullableAliasCapture(value: *s32?)->s32
{
    let read = func|pointer = value|()->s32
    {
        if pointer == null do
            return -1
        return pointer[]
    }
    return read()
}

#test
{
    var value: s32 = 42
    Swag.assert(readNullableCapture(&value) == 42)
    Swag.assert(readNullableCapture(null) == -1)
    Swag.assert(readNullableAliasCapture(&value) == 42)
    Swag.assert(readNullableAliasCapture(null) == -1)
}
