// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/Types.h"

struct AstNodeBlockBase : AstNodeBase
{
    explicit AstNodeBlockBase(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    Ref spanChildren;
};

struct AstNodeFile : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::File;
    AstNodeFile() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeTopLevelBlock : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::TopLevelBlock;
    AstNodeTopLevelBlock() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeEmbeddedBlock : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::EmbeddedBlock;
    AstNodeEmbeddedBlock() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeImplDecl : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::ImplDecl;
    AstNodeImplDecl() :
        AstNodeBlockBase(ID)
    {
    }

    AstNodeRef nodeIdentifier;
};

struct AstNodeImplDeclFor : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::ImplDeclFor;
    AstNodeImplDeclFor() :
        AstNodeBlockBase(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodeFor;
};

struct AstNodeNamespace : AstNodeBase
{
    static constexpr auto ID = AstNodeId::Namespace;
    AstNodeNamespace() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeName;
    AstNodeRef nodeBody;
};

struct AstNodeUsingNamespace : AstNodeBase
{
    static constexpr auto ID = AstNodeId::UsingNamespace;
    AstNodeUsingNamespace() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeNamespace;
};

struct AstNodeCall1Base : AstNodeBase
{
    explicit AstNodeCall1Base(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
};

struct AstNodeCall2Base : AstNodeBase
{
    explicit AstNodeCall2Base(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
};

struct AstNodeCall3Base : AstNodeBase
{
    explicit AstNodeCall3Base(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
    AstNodeRef nodeParam3;
};

struct AstNodeCompilerCall1 : AstNodeCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerCall1;
    AstNodeCompilerCall1() :
        AstNodeCall1Base(ID)
    {
    }
};

struct AstNodeIntrinsicCall1 : AstNodeCall1Base
{
    static constexpr auto ID = AstNodeId::IntrinsicCall1;
    AstNodeIntrinsicCall1() :
        AstNodeCall1Base(ID)
    {
    }
};

struct AstNodeIntrinsicCall2 : AstNodeCall2Base
{
    static constexpr auto ID = AstNodeId::IntrinsicCall2;
    AstNodeIntrinsicCall2() :
        AstNodeCall2Base(ID)
    {
    }
};

struct AstNodeIntrinsicCall3 : AstNodeCall3Base
{
    static constexpr auto ID = AstNodeId::IntrinsicCall3;
    AstNodeIntrinsicCall3() :
        AstNodeCall3Base(ID)
    {
    }
};

struct AstNodeFuncBody : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::FuncBody;
    AstNodeFuncBody() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeCompilerAssert : AstNodeCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerAssert;
    AstNodeCompilerAssert() :
        AstNodeCall1Base(ID)
    {
    }
};

struct AstNodeCompilerError : AstNodeCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerError;
    AstNodeCompilerError() :
        AstNodeCall1Base(ID)
    {
    }
};

struct AstNodeCompilerWarning : AstNodeCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerWarning;
    AstNodeCompilerWarning() :
        AstNodeCall1Base(ID)
    {
    }
};

struct AstNodeCompilerPrint : AstNodeCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerPrint;
    AstNodeCompilerPrint() :
        AstNodeCall1Base(ID)
    {
    }
};

struct AstNodeCompilerFunc : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CompilerFunc;
    explicit AstNodeCompilerFunc() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeBody;
};

struct AstNodeCompilerShortFunc : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CompilerShortFunc;
    explicit AstNodeCompilerShortFunc() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeExpr;
};

struct AstNodeCompilerFuncExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CompilerFuncExpr;
    explicit AstNodeCompilerFuncExpr() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeExpr;
};

struct AstNodeIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::Identifier;
    AstNodeIdentifier() :
        AstNodeBase(ID)
    {
    }

    TokenRef tknName;
};

struct AstNodeScopedIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ScopedIdentifier;
    AstNodeScopedIdentifier() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdentifier;
};

struct AstNodeUpIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::UpIdentifier;
    AstNodeUpIdentifier() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdentifier;
};

struct AstNodePostfixIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::PostfixIdentifier;
    AstNodePostfixIdentifier() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodePostfix;
};

struct AstNodeMultiPostfixIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::MultiPostfixIdentifier;
    AstNodeMultiPostfixIdentifier() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodePostfixBlock;
};

struct AstNodeFuncCall : AstNodeBase
{
    static constexpr auto ID = AstNodeId::FuncCall;
    AstNodeFuncCall() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstNodeStructInit : AstNodeBase
{
    static constexpr auto ID = AstNodeId::StructInit;
    AstNodeStructInit() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstNodeIndexExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::IndexExpr;
    AstNodeIndexExpr() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstNodeArgument : AstNodeBase
{
    explicit AstNodeArgument(AstNodeId nodeId) :
        AstNodeBase(nodeId)
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

struct AstNodeParenExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ParenExpr;
    AstNodeParenExpr() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
};

struct AstNodeNamedArgumentList : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::NamedArgumentList;
    AstNodeNamedArgumentList() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeUnnamedArgumentList : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::UnnamedArgumentList;
    AstNodeUnnamedArgumentList() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeBinaryBase : AstNodeBase
{
    explicit AstNodeBinaryBase(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    TokenRef   tknOp;
    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstNodeLogicalExpr : AstNodeBinaryBase
{
    static constexpr auto ID = AstNodeId::LogicalExpr;
    AstNodeLogicalExpr() :
        AstNodeBinaryBase(ID)
    {
    }
};

struct AstNodeRelationalExpr : AstNodeBinaryBase
{
    static constexpr auto ID = AstNodeId::RelationalExpr;
    AstNodeRelationalExpr() :
        AstNodeBinaryBase(ID)
    {
    }
};

struct AstNodeBinaryExpr : AstNodeBinaryBase
{
    static constexpr auto ID = AstNodeId::BinaryExpr;
    AstNodeBinaryExpr() :
        AstNodeBinaryBase(ID)
    {
    }

    AstModifierFlags modifiersFlags;
};

struct AstNodeUnaryExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::UnaryExpr;
    AstNodeUnaryExpr() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tknOp;
    AstNodeRef nodeExpr;
};

struct AstNodeLiteralBase : AstNodeBase
{
    explicit AstNodeLiteralBase(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    TokenRef tknValue;
};

struct AstNodeIntegerLiteral : AstNodeLiteralBase
{
    static constexpr auto ID = AstNodeId::IntegerLiteral;
    AstNodeIntegerLiteral() :
        AstNodeLiteralBase(ID)
    {
    }
};

struct AstNodeFloatLiteral : AstNodeLiteralBase
{
    static constexpr auto ID = AstNodeId::FloatLiteral;
    AstNodeFloatLiteral() :
        AstNodeLiteralBase(ID)
    {
    }
};

struct AstNodeStringLiteral : AstNodeLiteralBase
{
    static constexpr auto ID = AstNodeId::StringLiteral;
    AstNodeStringLiteral() :
        AstNodeLiteralBase(ID)
    {
    }
};

struct AstNodeCharacterLiteral : AstNodeLiteralBase
{
    static constexpr auto ID = AstNodeId::CharacterLiteral;
    AstNodeCharacterLiteral() :
        AstNodeLiteralBase(ID)
    {
    }
};

struct AstNodeBoolLiteral : AstNodeLiteralBase
{
    static constexpr auto ID = AstNodeId::BoolLiteral;
    AstNodeBoolLiteral() :
        AstNodeLiteralBase(ID)
    {
    }
};

struct AstNodeNullLiteral : AstNodeLiteralBase
{
    static constexpr auto ID = AstNodeId::NullLiteral;
    AstNodeNullLiteral() :
        AstNodeLiteralBase(ID)
    {
    }
};

struct AstNodeCompilerLiteral : AstNodeLiteralBase
{
    static constexpr auto ID = AstNodeId::CompilerLiteral;
    AstNodeCompilerLiteral() :
        AstNodeLiteralBase(ID)
    {
    }
};

struct AstNodeSuffixedLiteral : AstNodeBase
{
    static constexpr auto ID = AstNodeId::SuffixedLiteral;
    AstNodeSuffixedLiteral() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeLiteral;
    AstNodeRef nodeQuote;
};

struct AstNodeArrayLiteral : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::ArrayLiteral;
    AstNodeArrayLiteral() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeScopeAccess : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ScopeAccess;
    AstNodeScopeAccess() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstNodeAsExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::AsExpr;
    AstNodeAsExpr() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstNodeIsExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::IsExpr;
    AstNodeIsExpr() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstNodeCastAutoExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CastAutoExpr;
    AstNodeCastAutoExpr() :
        AstNodeBase(ID)
    {
    }

    TokenRef         tknOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExpr;
};

struct AstNodeCastExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CastExpr;
    AstNodeCastExpr() :
        AstNodeBase(ID)
    {
    }

    TokenRef         tknOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeType;
    AstNodeRef       nodeExpr;
};

struct AstNodeEnumDecl : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::EnumDecl;
    AstNodeEnumDecl() :
        AstNodeBlockBase(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeType;
};

struct AstNodeEnumValue : AstNodeBase
{
    static constexpr auto ID = AstNodeId::EnumValue;
    AstNodeEnumValue() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeValue;
};

struct AstNodeEnumUsingValue : AstNodeBase
{
    static constexpr auto ID = AstNodeId::EnumUsingValue;
    AstNodeEnumUsingValue() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeName;
};

struct AstNodeEnumImplDecl : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::EnumImplDecl;
    AstNodeEnumImplDecl() :
        AstNodeBlockBase(ID)
    {
    }

    AstNodeRef nodeName;
};

struct AstNodeQualifiedType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::QualifiedType;
    AstNodeQualifiedType() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tknQual;
    AstNodeRef nodeType;
};

struct AstNodeLRefType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::LRefType;
    explicit AstNodeLRefType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodeRRefType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::RRefType;
    explicit AstNodeRRefType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodePointerType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::PointerType;
    AstNodePointerType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeBlockPointerType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::BlockPointerType;
    AstNodeBlockPointerType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeSliceType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::SliceType;
    AstNodeSliceType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeIncompleteArrayType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::IncompleteArrayType;
    AstNodeIncompleteArrayType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeArrayType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ArrayType;
    AstNodeArrayType() :
        AstNodeBase(ID)
    {
    }

    Ref        spanDimensions;
    AstNodeRef nodePointeeType;
};

struct AstNodeNamedType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::NamedType;
    AstNodeNamedType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdentifier;
};

struct AstNodeBuiltinType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::BuiltinType;
    AstNodeBuiltinType() :
        AstNodeBase(ID)
    {
    }

    TokenRef tknType;
};

struct AstNodeCompilerType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CompilerType;
    AstNodeCompilerType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodeCompilerIf : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::CompilerIf;
    AstNodeCompilerIf() :
        AstNodeBlockBase(ID)
    {
    }

    TokenRef   tknIf;
    AstNodeRef nodeCondition;
    AstNodeRef nodeIfBlock;
    AstNodeRef nodeElseBlock;
};

struct AstNodeCompilerElse : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::CompilerElse;
    AstNodeCompilerElse() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeCompilerElseIf : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::CompilerElseIf;
    AstNodeCompilerElseIf() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeAttribute : AstNodeBase
{
    static constexpr auto ID = AstNodeId::Attribute;
    AstNodeAttribute() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodeArgs;
};

struct AstNodeAttributeBlock : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::AttributeBlock;
    AstNodeAttributeBlock() :
        AstNodeBlockBase(ID)
    {
    }

    AstNodeRef nodeBody;
};

struct AstNodeDependencies : AstNodeBase
{
    static constexpr auto ID = AstNodeId::Dependencies;
    AstNodeDependencies() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeBody;
};

struct AstNodeUsingDecl : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::UsingDecl;
    AstNodeUsingDecl() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeStructDeclBase : AstNodeBlockBase
{
    explicit AstNodeStructDeclBase(AstNodeId nodeId) :
        AstNodeBlockBase(nodeId)
    {
    }

    TokenRef tknName;
    Ref      spanGenericParams;
    Ref      spanWhere;
};

struct AstNodeStructDecl : AstNodeStructDeclBase
{
    static constexpr auto ID = AstNodeId::StructDecl;
    AstNodeStructDecl() :
        AstNodeStructDeclBase(ID)
    {
    }
};

struct AstNodeUnionDecl : AstNodeStructDeclBase
{
    static constexpr auto ID = AstNodeId::UnionDecl;
    AstNodeUnionDecl() :
        AstNodeStructDeclBase(ID)
    {
    }
};

struct AstNodeAccessModifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::AccessModifier;
    AstNodeAccessModifier() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tknAccess;
    AstNodeRef nodeWhat;
};

struct AstNodeConstraintBlock : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::ConstraintBlock;
    AstNodeConstraintBlock() :
        AstNodeBlockBase(ID)
    {
    }

    TokenRef tknConstraint;
};

struct AstNodeConstraintExpression : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ConstraintExpression;
    AstNodeConstraintExpression() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tknConstraint;
    AstNodeRef nodeExpr;
};

struct AstNodeGenericParamsBlock : AstNodeBlockBase
{
    static constexpr auto ID = AstNodeId::GenericParamsBlock;
    AstNodeGenericParamsBlock() :
        AstNodeBlockBase(ID)
    {
    }
};

struct AstNodeGenericParamBase : AstNodeBase
{
    explicit AstNodeGenericParamBase(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeAssign;
};

struct AstNodeGenericParamValue : AstNodeGenericParamBase
{
    static constexpr auto ID = AstNodeId::GenericParamValue;
    AstNodeGenericParamValue() :
        AstNodeGenericParamBase(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodeGenericParamType : AstNodeGenericParamBase
{
    static constexpr auto ID = AstNodeId::GenericParamType;
    AstNodeGenericParamType() :
        AstNodeGenericParamBase(ID)
    {
    }
};
