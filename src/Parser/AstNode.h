#pragma once
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;

// Your existing Flags<>. Keep this as-is.
enum class AstNodeIdArity : uint32_t
{
    None,
    One,
    Two,
    Many,
};

struct AstNodeIdInfo
{
    std::string_view name;
    AstNodeIdArity   arity;
};

enum class AstNodeId : uint16_t
{
    Invalid = 0,
#define SWC_NODE_ID_DEF(enum, arity) enum,
#include "AstNodeIds.inc"

#undef SWC_NODE_ID_DEF
    Count
};

constexpr std::array<AstNodeIdInfo, static_cast<size_t>(AstNodeId::Count)> AST_NODE_ID_INFOS = {
#define SWC_NODE_ID_DEF(enum, arity) AstNodeIdInfo{#enum, AstNodeIdArity::arity},
#include "AstNodeIds.inc"

#undef SWC_NODE_ID_DEF
};

struct AstChildrenMany
{
    uint32_t index = 0; // Index in Ast::nodeRefs_
    uint32_t count = 0;
};

struct AstChildrenOne
{
    AstNodeRef first;
};

struct AstChildrenTwo
{
    AstNodeRef first;
    AstNodeRef second;
};

struct AstChildrenView
{
    const AstNodeRef* ptr   = nullptr;
    uint32_t          count = 0;
    const AstNodeRef* begin() const { return ptr; }
    const AstNodeRef* end() const { return ptr + count; }
    size_t            size() const { return count; }
};

#pragma pack(push, 1)
struct AstNode
{
    AstNodeId id    = AstNodeId::Invalid;

    union
    {
        AstChildrenOne  one;
        AstChildrenTwo  two;
        AstChildrenMany many;
    };

    TokenRef  token = INVALID_REF;

    AstNode()
    {
    }

    AstNode(AstNodeId nodeId, TokenRef tok) :
        token(tok),
        id(nodeId)
    {
    }

    AstNode(AstNodeId nodeId, TokenRef tok, const AstChildrenOne& s) :
        token(tok),
        id(nodeId),
        one(s)
    {
    }

    AstNode(AstNodeId nodeId, TokenRef tok, const AstChildrenTwo& s) :
        token(tok),
        id(nodeId),
        two(s)
    {
    }

    AstNode(AstNodeId nodeId, TokenRef tok, const AstChildrenMany& s) :
        token(tok),
        id(nodeId),
        many(s)
    {
    }
};
#pragma pack(pop)

SWC_END_NAMESPACE();
