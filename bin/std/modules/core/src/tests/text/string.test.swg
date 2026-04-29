#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var value: String = " core "
    @assert(value == " core ")

    value.trim()
    @assert(value == "core")

    value.insert(0, "[")
    value.append("]")
    @assert(value == "[core]")

    value.remove(0)
    value.removeBack()
    @assert(value == "core")

    value.clear()
    @assert(value.isEmpty())
}

#test
{
    var value: String = "caf\u00E9"
    @assert(value.contains('\u00E9''rune))
    @assert(value.indexOf('\u00E9''rune) == 3)
}
