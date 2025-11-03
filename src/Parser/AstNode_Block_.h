// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/Types.h"

struct AstNodeBlock : AstNode
{
    explicit AstNodeBlock(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    Ref spanChildren;
};

struct AstNodeFile : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::File;
    AstNodeFile() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeTopLevelBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::TopLevelBlock;
    AstNodeTopLevelBlock() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeEmbeddedBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::EmbeddedBlock;
    AstNodeEmbeddedBlock() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeImplDecl : AstNode
{
    static constexpr auto ID = AstNodeId::ImplDecl;
    AstNodeImplDecl() :
        AstNode(ID)
    {
    }

    TokenRef   tknOp;
    AstNodeRef nodeIdentifier;
    AstNodeRef nodeContent;
};

struct AstNodeImplDeclFor : AstNode
{
    static constexpr auto ID = AstNodeId::ImplDeclFor;
    AstNodeImplDeclFor() :
        AstNode(ID)
    {
    }

    TokenRef   tknOp;
    AstNodeRef nodeIdentifier;

    AstNodeRef nodeFor;
    AstNodeRef nodeContent;
};

struct AstNodeNamespace : AstNode
{
    static constexpr auto ID = AstNodeId::Namespace;
    AstNodeNamespace() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeName;
    AstNodeRef nodeBody;
};
