#pragma once

SWC_BEGIN_NAMESPACE()

class SourceFile;

struct AstNodeIdInfo
{
    std::string_view name;
};

enum class AstNodeId : uint16_t
{
#define SWC_NODE_DEF(enum) enum,
#include "AstNodes.inc"

#undef SWC_NODE_DEF
    Count
};

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_DEF(enum) AstNodeIdInfo{#enum},
#include "AstNodes.inc"

#undef SWC_NODE_DEF
};

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
        flags_ |= val.flags;
    }

private:
    Flags flags_;
};

struct AstInvalid : AstNode
{
    static constexpr auto ID = AstNodeId::Invalid;
    AstInvalid() :
        AstNode(ID)
    {
    }
};

// ReSharper disable once CppUnusedIncludeDirective
#include "Parser/AstNodes.h"

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

template<AstNodeId ID>
struct AstTypeOf;

#define SWC_NODE_DEF(E)            \
    template<>                     \
    struct AstTypeOf<AstNodeId::E> \
    {                              \
        using type = Ast##E;       \
    };
// ReSharper disable once CppUnusedIncludeDirective
#include "AstNodes.inc"
#undef SWC_NODE_DEF

template<class F>
decltype(auto) visitAstNodeId(AstNodeId id, F f)
{
    switch (id)
    {
#define SWC_NODE_DEF(E) \
    case AstNodeId::E:  \
        return std::forward<F>(f).operator()<AstNodeId::E>();
#include "AstNodes.inc"

#undef SWC_NODE_DEF
    default:
        std::unreachable();
    }
}

SWC_END_NAMESPACE()
