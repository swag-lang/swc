// ReSharper disable CppPossiblyUninitializedMember
#pragma once

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
