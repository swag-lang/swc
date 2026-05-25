#global moduleprivate
using Swag

namespace AssumeBlockBindings
{
    func valueOrThrow(value: s32)->s32 throw
    {
        return value
    }

    func parseWithVarBindings()->s32
    {
        assume
        {
            var x0 = valueOrThrow(12)
            var y0 = valueOrThrow(34)
        }

        x0 += y0
        return x0
    }

    func parseWithLetBindings()->s32
    {
        assume
        {
            let x0 = valueOrThrow(7)
            let y0 = valueOrThrow(8)
        }

        return x0 + y0
    }
}

#test
{
    @assert(AssumeBlockBindings.parseWithVarBindings() == 46)
    @assert(AssumeBlockBindings.parseWithLetBindings() == 15)
}
