#global private
using Swag

#[Swag.NoInline, Swag.Optimize(true)]
func updateIndexedWords(values: *[16] u32)
{
    for i in 16 do values[][i] += 1
    for i in 16 do values[][i] -= 1
    for i in 16 do values[][i] ^= 0x35
}

func jitIndexedConstantUpdates()->bool
{
    var values: [16] u32
    for i in 16 do values[i] = cast(u32) i
    updateIndexedWords(&values)
    for i in 16 do if values[i] != (cast(u32) i ^ 0x35) do return false
    return true
}

#assert(#run jitIndexedConstantUpdates())

#test
{
    Swag.assert(jitIndexedConstantUpdates())
}
