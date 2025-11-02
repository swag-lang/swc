// ReSharper disable CppPossiblyUninitializedMember
#pragma once

struct AstNodeCallerSingleArg : AstNode
{
    explicit AstNodeCallerSingleArg(AstNodeId id) :
        AstNode(id)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeExpr;
};

struct AstNodeCompilerAssert : AstNodeCallerSingleArg
{
    static constexpr auto ID = AstNodeId::CompilerAssert;
    AstNodeCompilerAssert() :
        AstNodeCallerSingleArg(ID)
    {
    }
};

struct AstNodeCompilerError : AstNodeCallerSingleArg
{
    static constexpr auto ID = AstNodeId::CompilerError;
    AstNodeCompilerError() :
        AstNodeCallerSingleArg(ID)
    {
    }
};

struct AstNodeCompilerWarning : AstNodeCallerSingleArg
{
    static constexpr auto ID = AstNodeId::CompilerWarning;
    AstNodeCompilerWarning() :
        AstNodeCallerSingleArg(ID)
    {
    }
};

struct AstNodeCompilerPrint : AstNodeCallerSingleArg
{
    static constexpr auto ID = AstNodeId::CompilerPrint;
    AstNodeCompilerPrint() :
        AstNodeCallerSingleArg(ID)
    {
    }
};
