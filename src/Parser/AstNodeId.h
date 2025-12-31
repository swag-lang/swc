#pragma once

SWC_BEGIN_NAMESPACE()

enum class AstNodeId : uint16_t
{
#define SWC_NODE_DEF(__enum, __flags) __enum,
#include "Parser/AstNodes.Def.inc"

#undef SWC_NODE_DEF
    Count
};

SWC_END_NAMESPACE()
