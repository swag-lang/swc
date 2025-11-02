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
