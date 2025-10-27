#pragma once
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;

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
#define SWC_NODE_ID_DEF(enum, arity) enum,
#include "AstNodeIds.inc"

#undef SWC_NODE_ID_DEF
    Count
};

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_ID_DEF(enum, arity) AstNodeIdInfo{#enum, AstNodeIdArity::arity},
#include "AstNodeIds.inc"

#undef SWC_NODE_ID_DEF
};

#pragma pack(push, 1)
struct AstNode
{
    AstNodeId id    = AstNodeId::Invalid;
    uint16_t  flags = 0;
    TokenRef  token = INVALID_REF;

    AstNode(AstNodeId nodeId, TokenRef tok) :
        id(nodeId),
        token(tok)
    {
    }
};
#pragma pack(pop)

SWC_END_NAMESPACE();
