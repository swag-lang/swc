#global private

namespace DefinitionSpace
{
    const Bias = 7

    #[Swag.ConstExpr, Swag.Inline]
    func helper(value: s32)->s32 => value + Bias

    #[Swag.ConstExpr, Swag.Inline]
    func exposed(value: s32)->s32 => helper(value)

    #[Swag.Inline]
    func passthrough(value: s32)->s32 => value

    namespace Nested
    {
        #[Swag.Inline]
        func exposed(value: s32)->s32 => helper(value)
    }
}

namespace CallSpace
{
    const Bias = 1000

    #[Swag.ConstExpr]
    func helper(value: s32)->s32 => value - 999

    #[Swag.ConstExpr]
    func evaluate(value: s32)->s32 => DefinitionSpace.exposed(value)

    func(T) generic(value: T)->s32
    {
        discard value
        const Result = #run evaluate(35)
        return Result
    }

    #[Swag.NoInline]
    func runtime(Bias: s32)->s32
    {
        let value = DefinitionSpace.passthrough(Bias)
        return DefinitionSpace.exposed(value) + DefinitionSpace.Nested.exposed(Bias)
    }

    #test
    {
        Swag.require(generic(0) == 42)
        Swag.require(DefinitionSpace.exposed(35) == 42)
        let Bias = 35
        Swag.require(DefinitionSpace.passthrough(Bias) == 35)
        Swag.require(DefinitionSpace.exposed(Bias) == 42)
        Swag.require(DefinitionSpace.Nested.exposed(Bias) == 42)
    }

    #test
    {
        for value in [0's32, 1, 35, 100] do
            Swag.require(runtime(value) == 2 * (value + 7))
    }

}
