#global private

#[Swag.Macro]
func readParameterCapture(input: u32 = 41)->u32
{
    let callback = func|input|()->u32
    {
        return input
    }
    return callback()
}

#[Swag.Macro]
func readPointerParameterCapture(pixelUserData: *void? = null)->*void?
{
    let callback = func|pixelUserData|()->*void?
    {
        return pixelUserData
    }
    return callback()
}

#test
{
    var callerValue: u32 = 17
    Swag.assert(readParameterCapture(callerValue) == 17)
    Swag.assert(readParameterCapture(29) == 29)
    Swag.assert(readParameterCapture() == 41)
    Swag.assert(readPointerParameterCapture(&callerValue) == &callerValue)
    Swag.assert(readPointerParameterCapture(null) == null)
    Swag.assert(readPointerParameterCapture() == null)
}

#[Swag.Macro]
func captureParallelParameter(pixelUserData: *void? = null)
{
    parallel for |pixelUserData| index in 8'u64
    {
        if pixelUserData != null do
            (cast([*] u64) pixelUserData)[index] = index + 1
    }
}

#test
{
    var values: [8] u64
    captureParallelParameter(&values)
    for index in 8 do
        Swag.assert(values[index] == index + 1)
    captureParallelParameter()
}
