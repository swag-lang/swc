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

SWC_END_NAMESPACE()
