#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

struct AstNodeBlock : AstNode
{
    Ref      firstChild  = INVALID_REF;
    uint32_t numChildren = 0;

    AstNodeBlock(AstNodeId nodeId, TokenRef tok) :
        AstNode(nodeId, tok)
    {
    }
};

struct AstNodeDelimitedBlock : AstNode
{
    TokenRef closeToken  = INVALID_REF;
    Ref      firstChild  = INVALID_REF;
    uint32_t numChildren = 0;

    AstNodeDelimitedBlock(AstNodeId nodeId, TokenRef tok) :
        AstNode(nodeId, tok)
    {
    }
};

SWC_END_NAMESPACE();
