#pragma once
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;

struct AstNodeIdInfo
{
    std::string_view name;
};

enum class AstNodeId : uint16_t
{
#define SWC_NODE_ID_DEF(enum) enum,
#include "AstNodeIds.inc"

#undef SWC_NODE_ID_DEF
    Count
};

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_ID_DEF(enum) AstNodeIdInfo{#enum},
#include "AstNodeIds.inc"

#undef SWC_NODE_ID_DEF
};

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

#include "Parser/AstNode_Block_.h"
#include "Parser/AstNode_Compiler_.h"
#include "Parser/AstNode_Expression_.h"
#include "Parser/AstNode_Type_.h"

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
#include "AstNodeIds.inc"
#undef SWC_NODE_ID_DEF

template<class F>
decltype(auto) visitAstNodeId(AstNodeId id, F&& f)
{
    switch (id)
    {
#define SWC_NODE_ID_DEF(E) \
    case AstNodeId::E:     \
        return std::forward<F>(f).operator()<AstNodeId::E>();
#include "AstNodeIds.inc"

#undef SWC_NODE_ID_DEF
    default:
        std::unreachable();
    }
}

SWC_END_NAMESPACE()
