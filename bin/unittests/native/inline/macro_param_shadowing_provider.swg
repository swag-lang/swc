#global internal

namespace InlineMacroParamShadowing
{
    // 'count' is both a macro parameter and the parameter of a local function the macro
    // declares. Inside 'first' the name is the function's own: the macro argument must not be
    // substituted for it.
    #[Swag.Macro]
    func visitTwice(count: u32, contextData: *void? = null, stmt: #code(index: u32, data))
    {
        func first(start, count: u32, contextData: *void?)
        {
            second(start, count, contextData)
        }

        func second(start, count: u32, contextData: *void?)
        {
            var index = start
            for count
            {
                #inject(stmt, index = index, data = contextData)
                index += 1
            }
        }

        first(0, count, contextData)
        first(count, count, contextData)
    }

    // The same rule for a closure declared inside a macro body: its own 'value' parameter
    // shadows the macro parameter of the same name.
    #[Swag.Macro]
    func scaledSum(value, factor: s32)->s32
    {
        var total = 0
        let scale = func|&total, factor|(value: s32)
        {
            total += value * factor
        }
        scale(1)
        scale(2)
        return total + value
    }
}
