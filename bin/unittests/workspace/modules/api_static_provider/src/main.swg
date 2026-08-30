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

func depStringLength(text: string)->u64
{
    return text.count
}

struct DepCalculator
{
    public base: s32
}

struct StaticInferredDepOwner
{
    public namespaced: DepTools.DepNamespaced
}

struct StaticInlineBuffer
{
    public buffer: #null [*] u8
}

#[Swag.Opaque]
struct StaticOpaqueInline
{
    internal value: u32
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

impl StaticInlineBuffer
{
    #[Swag.Inline]
    mtd clearFirst()
    {
        if .buffer do
            .buffer[0] = 0
    }
}

impl StaticOpaqueInline
{
    mtd init(value: u32)
    {
        .value = value
    }

    #[Swag.Inline]
    mtd getValue()->u32 => .value
}
