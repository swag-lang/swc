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
    Swag.require(readParameterCapture(callerValue) == 17)
    Swag.require(readParameterCapture(29) == 29)
    Swag.require(readParameterCapture() == 41)
    Swag.require(readPointerParameterCapture(&callerValue) == &callerValue)
    Swag.require(readPointerParameterCapture(null) == null)
    Swag.require(readPointerParameterCapture() == null)
}

#[Swag.Macro]
func captureParallelParameter(pixelUserData: *void? = null)
{
    parallel for |pixelUserData| index in 8'u64
    {
        if pixelUserData != null do
            cast([*] u64, pixelUserData)[index] = index + 1
    }
}

#test
{
    var values: [8] u64
    captureParallelParameter(&values)
    for index in 8 do
        Swag.require(values[index] == index + 1)
    captureParallelParameter()
}
