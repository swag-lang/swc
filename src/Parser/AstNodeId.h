#pragma once

SWC_BEGIN_NAMESPACE()

enum class AstNodeId : uint16_t
{
#define SWC_NODE_DEF(__enum, __scopeFlags) __enum,
#include "Parser/AstNodesEnum.inc"

#undef SWC_NODE_DEF
    Count
};

SWC_END_NAMESPACE()
