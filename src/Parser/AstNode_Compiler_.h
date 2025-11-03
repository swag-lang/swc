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

struct AstNodeCompilerRunFunc : AstNodeCompilerFunc
{
    static constexpr auto ID = AstNodeId::CompilerRunFunc;
    AstNodeCompilerRunFunc() :
        AstNodeCompilerFunc(ID)
    {
    }
};

struct AstNodeCompilerTestFunc : AstNodeCompilerFunc
{
    static constexpr auto ID = AstNodeId::CompilerTestFunc;
    AstNodeCompilerTestFunc() :
        AstNodeCompilerFunc(ID)
    {
    }
};

struct AstNodeCompilerAstFunc : AstNodeCompilerFunc
{
    static constexpr auto ID = AstNodeId::CompilerAstFunc;
    AstNodeCompilerAstFunc() :
        AstNodeCompilerFunc(ID)
    {
    }
};

struct AstNodeCompilerInitFunc : AstNodeCompilerFunc
{
    static constexpr auto ID = AstNodeId::CompilerInitFunc;
    AstNodeCompilerInitFunc() :
        AstNodeCompilerFunc(ID)
    {
    }
};

struct AstNodeCompilerDropFunc : AstNodeCompilerFunc
{
    static constexpr auto ID = AstNodeId::CompilerDropFunc;
    AstNodeCompilerDropFunc() :
        AstNodeCompilerFunc(ID)
    {
    }
};

struct AstNodeCompilerMainFunc : AstNodeCompilerFunc
{
    static constexpr auto ID = AstNodeId::CompilerMainFunc;
    AstNodeCompilerMainFunc() :
        AstNodeCompilerFunc(ID)
    {
    }
};

struct AstNodeCompilerPreMainFunc : AstNodeCompilerFunc
{
    static constexpr auto ID = AstNodeId::CompilerPreMainFunc;
    AstNodeCompilerPreMainFunc() :
        AstNodeCompilerFunc(ID)
    {
    }
};