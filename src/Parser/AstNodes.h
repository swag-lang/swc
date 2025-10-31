#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

struct AstNodeBlock : AstNode
{
    AstNodeBlock(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    Ref nodeChildren;
};

struct AstNodeEnumDecl : AstNode
{
    AstNodeEnumDecl() :
        AstNode(AstNodeId::EnumDecl)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeType;
    AstNodeRef nodeBody;
};

struct AstNodeEnumValue : AstNode
{
    AstNodeEnumValue() :
        AstNode(AstNodeId::EnumValue)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeValue;
};

struct AstNodeQualifiedType : AstNode
{
    AstNodeQualifiedType() :
        AstNode(AstNodeId::QualifiedType)
    {
    }

    TokenRef   tknQual;
    AstNodeRef nodeType;
};

struct AstNodeRefType : AstNode
{
    AstNodeRefType(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodePointerType : AstNode
{
    AstNodePointerType() :
        AstNode(AstNodeId::PointerType)
    {
    }

    AstNodeRef pointeeType;
};

struct AstNodeBlockPointerType : AstNode
{
    AstNodeBlockPointerType() :
        AstNode(AstNodeId::BlockPointerType)
    {
    }

    AstNodeRef pointeeType;
};

struct AstNodeNamedType : AstNode
{
    AstNodeNamedType() :
        AstNode(AstNodeId::NamedType)
    {
    }

    TokenRef tknName;
};

struct AstNodeBuiltinType : AstNode
{
    AstNodeBuiltinType() :
        AstNode(AstNodeId::BuiltinType)
    {
    }

    TokenRef tknType;
};

SWC_END_NAMESPACE()
