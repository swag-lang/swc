#pragma once

SWC_BEGIN_NAMESPACE()

class SourceFile;

struct AstNodeIdInfo
{
    std::string_view name;
};

enum class AstNodeId : uint16_t
{
#define SWC_NODE_ID_DEF(enum) enum,
#include "AstNodes.def"

#undef SWC_NODE_ID_DEF
    Count
};

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_ID_DEF(enum) AstNodeIdInfo{#enum},
#include "AstNodes.def"

#undef SWC_NODE_ID_DEF
};

enum class AstModifierFlags : uint32_t
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
SWC_ENABLE_BITMASK(AstModifierFlags);

struct AstNode
{
    AstNodeId id    = AstNodeId::Invalid;
    uint16_t  flags = 0;

    explicit AstNode(AstNodeId nodeId) :
        id(nodeId)
    {
    }
};

struct AstNodeInvalid : AstNode
{
    static constexpr auto ID = AstNodeId::Invalid;
    AstNodeInvalid() :
        AstNode(ID)
    {
    }
};

#include "Parser/AstNodes.h"

template<typename T>
T* castAst(AstNode* node)
{
    SWC_ASSERT(node);
    SWC_ASSERT(node->id == T::ID);
    return reinterpret_cast<T*>(node);
}

template<AstNodeId Id>
struct AstTypeOf;

#define SWC_NODE_ID_DEF(E)         \
    template<>                     \
    struct AstTypeOf<AstNodeId::E> \
    {                              \
        using type = AstNode##E;   \
    };
#include "AstNodes.def"
#undef SWC_NODE_ID_DEF

template<class F>
decltype(auto) visitAstNodeId(AstNodeId id, F&& f)
{
    switch (id)
    {
#define SWC_NODE_ID_DEF(E) \
    case AstNodeId::E:     \
        return std::forward<F>(f).operator()<AstNodeId::E>();
#include "AstNodes.def"

#undef SWC_NODE_ID_DEF
    default:
        std::unreachable();
    }
}

SWC_END_NAMESPACE()
