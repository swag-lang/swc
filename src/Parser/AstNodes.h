#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

struct AstNodeBlock : AstNode
{
    Ref children = INVALID_REF;

    AstNodeBlock(AstNodeId nodeId, TokenRef tok) :
        AstNode(nodeId, tok)
    {
    }
};

struct AstNodeDelimitedBlock : AstNode
{
    TokenRef closeToken = INVALID_REF;
    Ref      children   = INVALID_REF;

    AstNodeDelimitedBlock(AstNodeId nodeId, TokenRef tok) :
        AstNode(nodeId, tok)
    {
    }
};

struct AstNodeEnumDecl : AstNode
{
    TokenRef   name;
    TokenRef   dotType;
    AstNodeRef type;
    AstNodeRef members;
};

SWC_END_NAMESPACE();
