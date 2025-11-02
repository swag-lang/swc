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

struct AstNodeParenExpression : AstNode
{
    static constexpr auto ID = AstNodeId::ParenExpression;
    AstNodeParenExpression() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
};

struct AstNodeBinary : AstNode
{
    explicit AstNodeBinary(AstNodeId nodeId) :
        AstNode(id)
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
