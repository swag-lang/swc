// ReSharper disable CppPossiblyUninitializedMember
#pragma once

struct AstNodeCompilerAssert : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerAssert;
    AstNodeCompilerAssert() :
        AstNode(ID)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeExpr;
};

struct AstNodeCompilerError : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerError;
    AstNodeCompilerError() :
        AstNode(ID)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeExpr;
};
