// ReSharper disable CppPossiblyUninitializedMember
#pragma once

struct AstNodeCompilerAssert : AstNodeCallerArg1
{
    static constexpr auto ID = AstNodeId::CompilerAssert;
    AstNodeCompilerAssert() :
        AstNodeCallerArg1(ID)
    {
    }
};

struct AstNodeCompilerError : AstNodeCallerArg1
{
    static constexpr auto ID = AstNodeId::CompilerError;
    AstNodeCompilerError() :
        AstNodeCallerArg1(ID)
    {
    }
};

struct AstNodeCompilerWarning : AstNodeCallerArg1
{
    static constexpr auto ID = AstNodeId::CompilerWarning;
    AstNodeCompilerWarning() :
        AstNodeCallerArg1(ID)
    {
    }
};

struct AstNodeCompilerPrint : AstNodeCallerArg1
{
    static constexpr auto ID = AstNodeId::CompilerPrint;
    AstNodeCompilerPrint() :
        AstNodeCallerArg1(ID)
    {
    }
};

struct AstNodeCompilerFunc : AstNode
{
    explicit AstNodeCompilerFunc(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeBody;
};

struct AstNodeCompilerTestFunc : AstNodeCompilerFunc
{
    static constexpr auto ID = AstNodeId::CompilerTestFunc;
    AstNodeCompilerTestFunc() :
        AstNodeCompilerFunc(ID)
    {
    }
};
