// ReSharper disable CppPossiblyUninitializedMember
#pragma once

struct AstNodeIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::Identifier;
    AstNodeIdentifier() :
        AstNode(ID)
    {
    }

    TokenRef tknName;
};

struct AstNodeScopedIdentifier : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::ScopedIdentifier;
    AstNodeScopedIdentifier() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeFuncCall : AstNode
{
    static constexpr auto ID = AstNodeId::FuncCall;
    AstNodeFuncCall() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstNodeStructInit : AstNode
{
    static constexpr auto ID = AstNodeId::StructInit;
    AstNodeStructInit() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstNodeArrayDeref : AstNode
{
    static constexpr auto ID = AstNodeId::ArrayDeref;
    AstNodeArrayDeref() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstNodeArgument : AstNode
{
    explicit AstNodeArgument(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }
};

struct AstNodeUnnamedArgument : AstNodeArgument
{
    static constexpr auto ID = AstNodeId::UnnamedArgument;
    AstNodeUnnamedArgument() :
        AstNodeArgument(ID)
    {
    }
};

struct AstNodeNamedArgument : AstNodeArgument
{
    static constexpr auto ID = AstNodeId::NamedArgument;
    AstNodeNamedArgument() :
        AstNodeArgument(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeArg;
};

struct AstNodeParenExpression : AstNode
{
    static constexpr auto ID = AstNodeId::ParenExpression;
    AstNodeParenExpression() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
};

struct AstNodeNamedArgumentBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::NamedArgumentBlock;
    AstNodeNamedArgumentBlock() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeUnnamedArgumentBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::UnnamedArgumentBlock;
    AstNodeUnnamedArgumentBlock() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeBinary : AstNode
{
    explicit AstNodeBinary(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tknOp;
    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstNodeBoolExpression : AstNodeBinary
{
    static constexpr auto ID = AstNodeId::BoolExpression;
    AstNodeBoolExpression() :
        AstNodeBinary(ID)
    {
    }
};

struct AstNodeCompareExpression : AstNodeBinary
{
    static constexpr auto ID = AstNodeId::CompareExpression;
    AstNodeCompareExpression() :
        AstNodeBinary(ID)
    {
    }
};

struct AstNodeFactorExpression : AstNodeBinary
{
    static constexpr auto ID = AstNodeId::FactorExpression;
    AstNodeFactorExpression() :
        AstNodeBinary(ID)
    {
    }

    AstModifierFlags modifiersFlags;
};

struct AstNodeUnaryExpression : AstNode
{
    static constexpr auto ID = AstNodeId::UnaryExpression;
    AstNodeUnaryExpression() :
        AstNode(ID)
    {
    }

    TokenRef   tknOp;
    AstNodeRef nodeExpr;
};

struct AstNodeLiteral : AstNode
{
    explicit AstNodeLiteral(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef tknValue;
};

struct AstNodeIntegerLiteral : AstNodeLiteral
{
    static constexpr auto ID = AstNodeId::IntegerLiteral;
    AstNodeIntegerLiteral() :
        AstNodeLiteral(ID)
    {
    }
};

struct AstNodeFloatLiteral : AstNodeLiteral
{
    static constexpr auto ID = AstNodeId::FloatLiteral;
    AstNodeFloatLiteral() :
        AstNodeLiteral(ID)
    {
    }
};

struct AstNodeStringLiteral : AstNodeLiteral
{
    static constexpr auto ID = AstNodeId::StringLiteral;
    AstNodeStringLiteral() :
        AstNodeLiteral(ID)
    {
    }
};

struct AstNodeCharacterLiteral : AstNodeLiteral
{
    static constexpr auto ID = AstNodeId::CharacterLiteral;
    AstNodeCharacterLiteral() :
        AstNodeLiteral(ID)
    {
    }
};

struct AstNodeBoolLiteral : AstNodeLiteral
{
    static constexpr auto ID = AstNodeId::BoolLiteral;
    AstNodeBoolLiteral() :
        AstNodeLiteral(ID)
    {
    }
};

struct AstNodeNullLiteral : AstNodeLiteral
{
    static constexpr auto ID = AstNodeId::NullLiteral;
    AstNodeNullLiteral() :
        AstNodeLiteral(ID)
    {
    }
};

struct AstNodeCompilerLiteral : AstNodeLiteral
{
    static constexpr auto ID = AstNodeId::CompilerLiteral;
    AstNodeCompilerLiteral() :
        AstNodeLiteral(ID)
    {
    }
};

struct AstNodeQuotedLiteral : AstNode
{
    static constexpr auto ID = AstNodeId::QuotedLiteral;
    AstNodeQuotedLiteral() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeLiteral;
    AstNodeRef nodeQuote;
};

struct AstNodeArrayLiteral : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::ArrayLiteral;
    AstNodeArrayLiteral() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeScopeAccess : AstNode
{
    static constexpr auto ID = AstNodeId::ScopeAccess;
    AstNodeScopeAccess() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstNodeAs : AstNode
{
    static constexpr auto ID = AstNodeId::As;
    AstNodeAs() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstNodeIs : AstNode
{
    static constexpr auto ID = AstNodeId::Is;
    AstNodeIs() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstNodeCastAuto : AstNode
{
    static constexpr auto ID = AstNodeId::CastAuto;
    AstNodeCastAuto() :
        AstNode(ID)
    {
    }

    TokenRef         tknOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExpr;
};

struct AstNodeCast : AstNode
{
    static constexpr auto ID = AstNodeId::Cast;
    AstNodeCast() :
        AstNode(ID)
    {
    }

    TokenRef         tknOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeType;
    AstNodeRef       nodeExpr;
};
