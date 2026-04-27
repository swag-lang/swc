#global fileprivate

#test
{
    var value: s32 = 0
    CrossFileMacroRegression.runWhen(value == 0, #code {
        value = 42
    })
    @assert(value == 42)
}
