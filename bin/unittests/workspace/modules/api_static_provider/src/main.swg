#global public
using ExportApi

func depDouble(value: s32)->s32
{
    return value * 2
}

func depScale(value: s32)->s32
{
    return value * 4
}

func depScale(value: f32)->f32
{
    return value * 4
}

func depStringLength(text: #nonull string)->u64
{
    return @countof(text)
}

struct DepCalculator
{
    base: s32
}

struct StaticInferredDepOwner
{
    namespaced: DepTools.DepNamespaced
}

impl DepCalculator
{
    func make(base: s32)->DepCalculator
    {
        return {base}
    }

    func resolve(value: s32)->s32
    {
        return value + 100
    }

    mtd const add(value: s32)->s32
    {
        return .base + value
    }

    mtd const addTwice(value: s32)->s32 => .add(value) + value
}

impl StaticInferredDepOwner
{
    #[Swag.Inline]
    mtd getNamespaced() => &.namespaced
}
