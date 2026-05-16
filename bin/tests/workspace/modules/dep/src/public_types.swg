#global public

alias DepCount = s32

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

namespace DepTools
{
    struct DepNamespaced
    {
        value: s16
    }
}
