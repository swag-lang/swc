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

struct AstNodeImplDecl : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::ImplDecl;
    AstNodeImplDecl() :
        AstNodeBlock(ID)
    {
    }

    AstNodeRef nodeIdentifier;
};

struct AstNodeImplDeclFor : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::ImplDeclFor;
    AstNodeImplDeclFor() :
        AstNodeBlock(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodeFor;
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

struct AstNodeUsingNamespace : AstNode
{
    static constexpr auto ID = AstNodeId::UsingNamespace;
    AstNodeUsingNamespace() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeNamespace;
};

struct AstNodeCall1 : AstNode
{
    explicit AstNodeCall1(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
};

struct AstNodeCall2 : AstNode
{
    explicit AstNodeCall2(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
};

struct AstNodeCall3 : AstNode
{
    explicit AstNodeCall3(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
    AstNodeRef nodeParam3;
};

struct AstNodeCompilerCall1 : AstNodeCall1
{
    static constexpr auto ID = AstNodeId::CompilerCall1;
    AstNodeCompilerCall1() :
        AstNodeCall1(ID)
    {
    }
};

struct AstNodeIntrinsicCall1 : AstNodeCall1
{
    static constexpr auto ID = AstNodeId::IntrinsicCall1;
    AstNodeIntrinsicCall1() :
        AstNodeCall1(ID)
    {
    }
};

struct AstNodeIntrinsicCall2 : AstNodeCall2
{
    static constexpr auto ID = AstNodeId::IntrinsicCall2;
    AstNodeIntrinsicCall2() :
        AstNodeCall2(ID)
    {
    }
};

struct AstNodeIntrinsicCall3 : AstNodeCall3
{
    static constexpr auto ID = AstNodeId::IntrinsicCall3;
    AstNodeIntrinsicCall3() :
        AstNodeCall3(ID)
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

struct AstNodeCompilerAssert : AstNodeCall1
{
    static constexpr auto ID = AstNodeId::CompilerAssert;
    AstNodeCompilerAssert() :
        AstNodeCall1(ID)
    {
    }
};

struct AstNodeCompilerError : AstNodeCall1
{
    static constexpr auto ID = AstNodeId::CompilerError;
    AstNodeCompilerError() :
        AstNodeCall1(ID)
    {
    }
};

struct AstNodeCompilerWarning : AstNodeCall1
{
    static constexpr auto ID = AstNodeId::CompilerWarning;
    AstNodeCompilerWarning() :
        AstNodeCall1(ID)
    {
    }
};

struct AstNodeCompilerPrint : AstNodeCall1
{
    static constexpr auto ID = AstNodeId::CompilerPrint;
    AstNodeCompilerPrint() :
        AstNodeCall1(ID)
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

struct AstNodeCompilerShortFunc : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerShortFunc;
    explicit AstNodeCompilerShortFunc() :
        AstNode(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeExpression;
};

struct AstNodeCompilerFuncExpr : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerFuncExpr;
    explicit AstNodeCompilerFuncExpr() :
        AstNode(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeExpression;
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

struct AstNodeScopedIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::ScopedIdentifier;
    AstNodeScopedIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdentifier;
};

struct AstNodeUpIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::UpIdentifier;
    AstNodeUpIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdentifier;
};

struct AstNodeSuffixedIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::SuffixedIdentifier;
    AstNodeSuffixedIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodeSuffix;
};

struct AstNodeMultiSuffixedIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::MultiSuffixedIdentifier;
    AstNodeMultiSuffixedIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodeSuffixBlock;
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

struct AstNodeLogicalExpression : AstNodeBinary
{
    static constexpr auto ID = AstNodeId::LogicalExpression;
    AstNodeLogicalExpression() :
        AstNodeBinary(ID)
    {
    }
};

struct AstNodeRelationalExpression : AstNodeBinary
{
    static constexpr auto ID = AstNodeId::RelationalExpression;
    AstNodeRelationalExpression() :
        AstNodeBinary(ID)
    {
    }
};

struct AstNodeBinaryExpression : AstNodeBinary
{
    static constexpr auto ID = AstNodeId::BinaryExpression;
    AstNodeBinaryExpression() :
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

struct AstNodeSuffixedLiteral : AstNode
{
    static constexpr auto ID = AstNodeId::SuffixedLiteral;
    AstNodeSuffixedLiteral() :
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

struct AstNodeEnumDecl : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::EnumDecl;
    AstNodeEnumDecl() :
        AstNodeBlock(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeType;
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

    AstNodeRef nodeName;
};

struct AstNodeEnumImplDecl : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::EnumImplDecl;
    AstNodeEnumImplDecl() :
        AstNodeBlock(ID)
    {
    }

    AstNodeRef nodeName;
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

    Ref        spanDimensions;
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

struct AstNodeCompilerType : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerType;
    AstNodeCompilerType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodeCompilerIf : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::CompilerIf;
    AstNodeCompilerIf() :
        AstNodeBlock(ID)
    {
    }

    TokenRef   tknIf;
    AstNodeRef nodeCondition;
    AstNodeRef nodeIfBlock;
    AstNodeRef nodeElseBlock;
};

struct AstNodeCompilerElse : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::CompilerElse;
    AstNodeCompilerElse() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeCompilerElseIf : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::CompilerElseIf;
    AstNodeCompilerElseIf() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeAttribute : AstNode
{
    static constexpr auto ID = AstNodeId::Attribute;
    AstNodeAttribute() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodeArgs;
};

struct AstNodeAttributeBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::AttributeBlock;
    AstNodeAttributeBlock() :
        AstNodeBlock(ID)
    {
    }

    AstNodeRef nodeBody;
};

struct AstNodeDependencies : AstNode
{
    static constexpr auto ID = AstNodeId::Dependencies;
    AstNodeDependencies() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeBody;
};

struct AstNodeUsingDecl : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::UsingDecl;
    AstNodeUsingDecl() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeStructDecl : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::StructDecl;
    AstNodeStructDecl() :
        AstNodeBlock(ID)
    {
    }

    TokenRef tknName;
    Ref      spanWhere;
};

struct AstNodeAccessModifier : AstNode
{
    static constexpr auto ID = AstNodeId::StructDecl;
    AstNodeAccessModifier() :
        AstNode(ID)
    {
    }

    TokenRef   tknAccess;
    AstNodeRef nodeWhat;
};

struct AstNodeConstraintBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::ConstraintBlock;
    AstNodeConstraintBlock() :
        AstNodeBlock(ID)
    {
    }

    TokenRef tknConstraint;
};

struct AstNodeConstraintExpression : AstNode
{
    static constexpr auto ID = AstNodeId::ConstraintExpression;
    AstNodeConstraintExpression() :
        AstNode(ID)
    {
    }

    TokenRef   tknConstraint;
    AstNodeRef nodeExpr;
};
