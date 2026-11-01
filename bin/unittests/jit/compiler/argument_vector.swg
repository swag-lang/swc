#global private

#run
{
    let info = Swag.processInfo()
    let saved = info.arguments
    defer info.arguments = saved
    let values: [6] string = ["", "two words", "a\"b", "tail\\", "\t", "café"]
    info.arguments = Swag.makeSlice(&values[0], values.count)
    let actual = Swag.args()
    Swag.assert(actual.count == values.count)
    for expected, index in values do
        Swag.assert(actual[index] == expected)
}
