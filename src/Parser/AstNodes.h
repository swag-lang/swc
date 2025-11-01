#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

struct AstNodeIdentifier : AstNode
{
    AstNodeIdentifier() :
        AstNode(AstNodeId::Identifier)
    {
    }

    TokenRef tknName;
};

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

struct AstNodeEnumUsingValue : AstNode
{
    AstNodeEnumUsingValue() :
        AstNode(AstNodeId::EnumUsingValue)
    {
    }

    TokenRef tknName;
};

struct AstNodeEnumImpl : AstNode
{
    AstNodeEnumImpl() :
        AstNode(AstNodeId::EnumImpl)
    {
    }

    AstNodeRef nodeName;
    AstNodeRef nodeBody;
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

    AstNodeRef nodePointeeType;
};

struct AstNodeBlockPointerType : AstNode
{
    AstNodeBlockPointerType() :
        AstNode(AstNodeId::BlockPointerType)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeSliceType : AstNode
{
    AstNodeSliceType() :
        AstNode(AstNodeId::SliceType)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeIncompleteArrayType : AstNode
{
    AstNodeIncompleteArrayType() :
        AstNode(AstNodeId::IncompleteArrayType)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeArrayType : AstNode
{
    AstNodeArrayType() :
        AstNode(AstNodeId::ArrayType)
    {
    }

    AstNodeRef nodeDim;
    AstNodeRef nodePointeeType;
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
