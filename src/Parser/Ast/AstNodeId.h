#pragma once

SWC_BEGIN_NAMESPACE();

enum class AstNodeId : uint8_t
{
#define SWC_NODE_DEF(__enum, __flags) __enum,
#include "Parser/Ast/AstNodes.Def.inc"

#undef SWC_NODE_DEF
    Count
};

SWC_END_NAMESPACE();
