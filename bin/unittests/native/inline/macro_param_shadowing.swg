#global private

// Runtime arguments: a constant argument is bound as a constant and never reaches the clone
// paths that substitute a name.
func runMacro(count: u32)->u32
{
    var sum = 0'u32
    InlineMacroParamShadowing.visitTwice(count, &sum) #code(index, data)
    {
        let total = cast(*u32) data!
        total[] += index
    }
    return sum
}

func runClosure(value, factor: s32)->s32 => InlineMacroParamShadowing.scaledSum(value, factor)

#test
{
    Swag.assert(runMacro(3) == 0 + 1 + 2 + 3 + 4 + 5)
    Swag.assert(runMacro(1) == 0 + 1)
    Swag.assert(runClosure(7, 10) == 37)
}
