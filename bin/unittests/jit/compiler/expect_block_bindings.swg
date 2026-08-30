#global internal
using Swag

namespace ExpectBlockBindings
{
    func valueOrFail(value: s32)->s32 fail
    {
        return value
    }

    func parseWithVarBindings()->s32
    {
        expect
        {
            var x0 = valueOrFail(12)
            var y0 = valueOrFail(34)
        }

        x0 += y0
        return x0
    }

    func parseWithLetBindings()->s32
    {
        expect
        {
            let x0 = valueOrFail(7)
            let y0 = valueOrFail(8)
        }

        return x0 + y0
    }
}

#test
{
    Swag.assert(ExpectBlockBindings.parseWithVarBindings() == 46)
    Swag.assert(ExpectBlockBindings.parseWithLetBindings() == 15)
}
