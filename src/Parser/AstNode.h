#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNodeId.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;

enum class AstModifierFlagsE : uint32_t
{
    Zero     = 0,
    Bit      = 1 << 0,
    UnConst  = 1 << 1,
    Err      = 1 << 2,
    NoErr    = 1 << 3,
    Promote  = 1 << 4,
    Wrap     = 1 << 5,
    NoDrop   = 1 << 6,
    Ref      = 1 << 7,
    ConstRef = 1 << 8,
    Reverse  = 1 << 9,
    Move     = 1 << 10,
    MoveRaw  = 1 << 11,
    Nullable = 1 << 12,
};
using AstModifierFlags = EnumFlags<AstModifierFlagsE>;

struct AstNode
{
    AstNodeId id = AstNodeId::Invalid;

    // ReSharper disable once CppPossiblyUninitializedMember
    explicit AstNode(AstNodeId nodeId) :
        id(nodeId)
    {
    }

    using Flags = uint16_t;

    template<typename T>
    EnumFlags<T> flags() const
    {
        return static_cast<EnumFlags<T>>(flags_);
    }

    void clearFlags()
    {
        flags_ = 0;
    }

    template<typename T>
    void addFlag(T val)
    {
        if constexpr (std::is_enum_v<T>)
            flags_ |= static_cast<std::underlying_type_t<T>>(val);
        else
            flags_ |= val.flags;
    }

    static void collectChildren(SmallVector<AstNodeRef>& out) {}

private:
    Flags flags_;
};

template<typename T>
T* castAst(AstNode* node)
{
    SWC_ASSERT(node);
    SWC_ASSERT(node->id == T::ID);
    return reinterpret_cast<T*>(node);
}

template<typename T>
const T* castAst(const AstNode* node)
{
    SWC_ASSERT(node);
    SWC_ASSERT(node->id == T::ID);
    return reinterpret_cast<const T*>(node);
}

SWC_END_NAMESPACE()
