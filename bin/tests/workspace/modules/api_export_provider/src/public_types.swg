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
