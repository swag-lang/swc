#global public

alias DepCount = s32

enum DepMode: s16
{
    Zero = 0
    Big  = 42
}

struct DepPair
{
    left:  DepCount
    right: s32
}

struct DepPublicWithPrivateField
{
    publicValue: s32

    moduleprivate
    {
        hiddenValue: s32
    }
}

struct DepPublicWithPrivateInlineUnion
{
    publicValue: s32

    moduleprivate
    {
        using bounds: union
        {
            signed:   { min: s32, max: s32 } = {0, 0}
            floating: { min: f32, max: f32 } = {0, 0}
        }
    }
}

func makeDepPublicWithPrivateField(value: s32)->DepPublicWithPrivateField
{
    return {publicValue: value, hiddenValue: value + 1}
}

struct(T) DepGenericLayout
{
    value: T
}

union DepValue
{
    asInt:   s32
    asFloat: f32
}

#[Swag.Opaque]
struct DepOpaque
{
    opaqueHead: u64
    opaqueTail: u32
}

#[Swag.Opaque]
struct DepOpaqueGenericBox
{
    moduleprivate seed: s32
}

impl DepOpaqueGenericBox
{
    mtd init(seed: s32)
    {
        .seed = seed
    }

    mtd(T) addSeed(value: T)->T
    {
        return value + cast(T) .seed
    }
}

interface IDepScore
{
    mtd score(value: s32)->s32;
}

namespace DepTools
{
    struct DepNamespaced
    {
        value: s16
    }
}

namespace DepSharedRng
{
    struct MWC
    {
        value: u32 = 0x12345678
    }

    impl MWC
    {
        mtd nextU32()->u32 => .value
    }

    #[Swag.Opaque]
    struct(T = MWC) Rng
    {
        rng: T
    }

    impl Rng
    {
        #[Inline]
        func(TA) makeScratch()->Rng'TA
        {
            var result: retval
            return result
        }

        mtd nextU32()->u32 => 0x12345678
    }

    public func shared(rng: *Rng'MWC)->*Rng'MWC => rng
}
