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

struct AstKidsSlice
{
    uint32_t index = 0; // Index in Ast::nodeRefs_
    uint32_t count = 0;
};

struct AstKidsOne
{
    AstNodeRef first;
};

struct AstKidsTwo
{
    AstNodeRef first;
    AstNodeRef second;
};

struct AstChildrenView
{
    const AstNodeRef* ptr = nullptr;
    uint32_t          n   = 0;
    const AstNodeRef* begin() const { return ptr; }
    const AstNodeRef* end() const { return ptr + n; }
    size_t            size() const { return n; }
};

struct AstNode
{
    AstNodeId id    = AstNodeId::Invalid;
    TokenRef  token = INVALID_REF;

    union
    {
        AstKidsSlice slice{};
        AstKidsOne   one;
        AstKidsTwo   two;
    };

    AstNode()
    {
    }

    AstNode(AstNodeId nodeId, TokenRef tok) :
        id(nodeId),
        token(tok)
    {
    }

    AstNode(AstNodeId nodeId, TokenRef tok, const AstKidsOne& s) :
        id(nodeId),
        token(tok),
        one(s)
    {
    }

    AstNode(AstNodeId nodeId, TokenRef tok, const AstKidsTwo& s) :
        id(nodeId),
        token(tok),
        two(s)
    {
    }

    AstNode(AstNodeId nodeId, TokenRef tok, const AstKidsSlice& s) :
        id(nodeId),
        token(tok),
        slice(s)
    {
    }
};

SWC_END_NAMESPACE();
