#pragma once
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;

// Your existing Flags<>. Keep this as-is.
enum class AstNodeIdFlagsEnum : uint32_t
{
    Zero      = 0,
    ArityNone = 1u << 0,
    ArityOne  = 1u << 1,
    ArityTwo  = 1u << 2,
    ArityMany = 1u << 3,
};

using AstNodeIdFlagsFlags = Flags<AstNodeIdFlagsEnum>;

struct AstNodeIdInfo
{
    std::string_view    name;
    AstNodeIdFlagsFlags flags;
};

enum class AstNodeId : uint16_t
{
    Invalid = 0,
#define SWC_NODE_ID_DEF(enum, flags) enum,
#include "AstNodeIds.inc"

#undef SWC_NODE_ID_DEF
    Count
};

constexpr std::array<AstNodeIdInfo, static_cast<size_t>(AstNodeId::Count)> AST_NODE_ID_INFOS = {
#define SWC_NODE_ID_DEF(enum, flags) AstNodeIdInfo{#enum, AstNodeIdFlagsEnum::flags},
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
        token(tok),
        id(nodeId)
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
