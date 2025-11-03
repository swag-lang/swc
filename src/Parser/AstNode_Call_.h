// ReSharper disable CppPossiblyUninitializedMember
#pragma once

struct AstNodeCallerArg1 : AstNode
{
    explicit AstNodeCallerArg1(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
};

struct AstNodeCallerArg2 : AstNode
{
    explicit AstNodeCallerArg2(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
};

struct AstNodeCallerArg3 : AstNode
{
    explicit AstNodeCallerArg3(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
    AstNodeRef nodeParam3;
};

struct AstNodeCompilerIntrinsic1 : AstNodeCallerArg1
{
    static constexpr auto ID = AstNodeId::CompilerIntrinsic1;
    AstNodeCompilerIntrinsic1() :
        AstNodeCallerArg1(ID)
    {
    }
};

struct AstNodeIntrinsic1 : AstNodeCallerArg1
{
    static constexpr auto ID = AstNodeId::Intrinsic1;
    AstNodeIntrinsic1() :
        AstNodeCallerArg1(ID)
    {
    }
};

struct AstNodeIntrinsic2 : AstNodeCallerArg2
{
    static constexpr auto ID = AstNodeId::Intrinsic2;
    AstNodeIntrinsic2() :
        AstNodeCallerArg2(ID)
    {
    }
};

struct AstNodeIntrinsic3 : AstNodeCallerArg3
{
    static constexpr auto ID = AstNodeId::Intrinsic3;
    AstNodeIntrinsic3() :
        AstNodeCallerArg3(ID)
    {
    }
};

struct AstNodeFuncBody : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::FuncBody;
    AstNodeFuncBody() :
        AstNodeBlock(ID)
    {
    }
};
