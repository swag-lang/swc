#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

struct AstNodeCompound : AstNode
{
    Ref      firstChild;
    uint32_t numChildren;

    AstNodeCompound() = delete;
    AstNodeCompound(AstNodeId id, TokenRef tok) :
        AstNode(id, tok),
        firstChild(INVALID_REF),
        numChildren(0)
    {
    }
};

SWC_END_NAMESPACE();
