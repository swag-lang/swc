#pragma once

SWC_BEGIN_NAMESPACE()

enum class AstNodeId : uint16_t
{
#define SWC_NODE_DEF(enum) enum,
#include "Parser/AstNodes.inc"

#undef SWC_NODE_DEF
    Count
};

SWC_END_NAMESPACE()
