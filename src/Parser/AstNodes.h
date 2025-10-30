#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

struct AstNodeBlock : AstNode
{
    Ref children = INVALID_REF;

    AstNodeBlock(AstNodeId nodeId, TokenRef tok) :
        AstNode(nodeId, tok)
    {
    }
};

struct AstNodeEnumDecl : AstNode
{
    AstNodeEnumDecl() : AstNode(AstNodeId::EnumDecl) {}

    TokenRef   name;
    AstNodeRef type;
    AstNodeRef body;
};

struct AstNodeEnumValue : AstNode
{
    AstNodeEnumValue() : AstNode(AstNodeId::EnumValue) {}

    TokenRef   name;
    AstNodeRef value;
};

SWC_END_NAMESPACE()
