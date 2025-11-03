// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/Types.h"

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

struct AstNodeEmbeddedBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::EmbeddedBlock;
    AstNodeEmbeddedBlock() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeImplDecl : AstNode
{
    static constexpr auto ID = AstNodeId::ImplDecl;
    AstNodeImplDecl() :
        AstNode(ID)
    {
    }

    TokenRef   tknOp;
    AstNodeRef nodeIdentifier;
    AstNodeRef nodeContent;
};

struct AstNodeImplDeclFor : AstNode
{
    static constexpr auto ID = AstNodeId::ImplDeclFor;
    AstNodeImplDeclFor() :
        AstNode(ID)
    {
    }

    TokenRef   tknOp;
    AstNodeRef nodeIdentifier;

    AstNodeRef nodeFor;
    AstNodeRef nodeContent;
};

struct AstNodeNamespace : AstNode
{
    static constexpr auto ID = AstNodeId::Namespace;
    AstNodeNamespace() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeName;
    AstNodeRef nodeBody;
};

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
    static constexpr auto ID = AstNodeId::CompilerFunc;
    explicit AstNodeCompilerFunc() :
        AstNode(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeBody;
};

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

struct AstNodeEnumDecl : AstNode
{
    static constexpr auto ID = AstNodeId::EnumDecl;
    AstNodeEnumDecl() :
        AstNode(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeType;
    AstNodeRef nodeBody;
};

struct AstNodeEnumBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::EnumBlock;
    AstNodeEnumBlock() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeEnumValue : AstNode
{
    static constexpr auto ID = AstNodeId::EnumValue;
    AstNodeEnumValue() :
        AstNode(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeValue;
};

struct AstNodeEnumUsingValue : AstNode
{
    static constexpr auto ID = AstNodeId::EnumUsingValue;
    AstNodeEnumUsingValue() :
        AstNode(ID)
    {
    }

    TokenRef tknName;
};

struct AstNodeEnumImpl : AstNode
{
    static constexpr auto ID = AstNodeId::EnumImpl;
    AstNodeEnumImpl() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeName;
    AstNodeRef nodeBody;
};

struct AstNodeQualifiedType : AstNode
{
    static constexpr auto ID = AstNodeId::QualifiedType;
    AstNodeQualifiedType() :
        AstNode(ID)
    {
    }

    TokenRef   tknQual;
    AstNodeRef nodeType;
};

struct AstNodeLRefType : AstNode
{
    static constexpr auto ID = AstNodeId::LRefType;
    explicit AstNodeLRefType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodeRRefType : AstNode
{
    static constexpr auto ID = AstNodeId::RRefType;
    explicit AstNodeRRefType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodePointerType : AstNode
{
    static constexpr auto ID = AstNodeId::PointerType;
    AstNodePointerType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeBlockPointerType : AstNode
{
    static constexpr auto ID = AstNodeId::BlockPointerType;
    AstNodeBlockPointerType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeSliceType : AstNode
{
    static constexpr auto ID = AstNodeId::SliceType;
    AstNodeSliceType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeIncompleteArrayType : AstNode
{
    static constexpr auto ID = AstNodeId::IncompleteArrayType;
    AstNodeIncompleteArrayType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeArrayType : AstNode
{
    static constexpr auto ID = AstNodeId::ArrayType;
    AstNodeArrayType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeDim;
    AstNodeRef nodePointeeType;
};

struct AstNodeNamedType : AstNode
{
    static constexpr auto ID = AstNodeId::NamedType;
    AstNodeNamedType() :
        AstNode(ID)
    {
    }

    TokenRef tknName;
};

struct AstNodeBuiltinType : AstNode
{
    static constexpr auto ID = AstNodeId::BuiltinType;
    AstNodeBuiltinType() :
        AstNode(ID)
    {
    }

    TokenRef tknType;
};
