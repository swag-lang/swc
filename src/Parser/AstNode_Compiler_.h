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
