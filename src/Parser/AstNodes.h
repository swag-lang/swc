// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/Types.h"

struct AstCompoundBase : AstNode
{
    explicit AstCompoundBase(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    SpanRef spanChildren;
};

struct AstFileBlock : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::FileBlock;
    AstFileBlock() :
        AstCompoundBase(ID)
    {
    }
};

struct AstTopLevelBlock : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::TopLevelBlock;
    AstTopLevelBlock() :
        AstCompoundBase(ID)
    {
    }
};

struct AstEmbeddedBlock : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::EmbeddedBlock;
    AstEmbeddedBlock() :
        AstCompoundBase(ID)
    {
    }
};

struct AstImplDecl : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::ImplDecl;
    AstImplDecl() :
        AstCompoundBase(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstImplDeclFor : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::ImplDeclFor;
    AstImplDeclFor() :
        AstCompoundBase(ID)
    {
    }

    AstNodeRef nodeIdent;
    AstNodeRef nodeFor;
};

struct AstNamespaceBlock : AstNode
{
    static constexpr auto ID = AstNodeId::NamespaceBlock;
    AstNamespaceBlock() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeName;
    AstNodeRef nodeBody;
};

struct AstUsingNamespace : AstNode
{
    static constexpr auto ID = AstNodeId::UsingNamespace;
    AstUsingNamespace() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeNamespace;
};

struct AstCall1Base : AstNode
{
    explicit AstCall1Base(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
};

struct AstCall2Base : AstNode
{
    explicit AstCall2Base(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
};

struct AstCall3Base : AstNode
{
    explicit AstCall3Base(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
    AstNodeRef nodeParam3;
};

struct AstCompilerCall1 : AstCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerCall1;
    AstCompilerCall1() :
        AstCall1Base(ID)
    {
    }
};

struct AstIntrinsicCall1 : AstCall1Base
{
    static constexpr auto ID = AstNodeId::IntrinsicCall1;
    AstIntrinsicCall1() :
        AstCall1Base(ID)
    {
    }
};

struct AstIntrinsicCall2 : AstCall2Base
{
    static constexpr auto ID = AstNodeId::IntrinsicCall2;
    AstIntrinsicCall2() :
        AstCall2Base(ID)
    {
    }
};

struct AstIntrinsicCall3 : AstCall3Base
{
    static constexpr auto ID = AstNodeId::IntrinsicCall3;
    AstIntrinsicCall3() :
        AstCall3Base(ID)
    {
    }
};

struct AstFuncBody : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::FuncBody;
    AstFuncBody() :
        AstCompoundBase(ID)
    {
    }
};

struct AstCompilerAssert : AstCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerAssert;
    AstCompilerAssert() :
        AstCall1Base(ID)
    {
    }
};

struct AstCompilerError : AstCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerError;
    AstCompilerError() :
        AstCall1Base(ID)
    {
    }
};

struct AstCompilerWarning : AstCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerWarning;
    AstCompilerWarning() :
        AstCall1Base(ID)
    {
    }
};

struct AstCompilerPrint : AstCall1Base
{
    static constexpr auto ID = AstNodeId::CompilerPrint;
    AstCompilerPrint() :
        AstCall1Base(ID)
    {
    }
};

struct AstCompilerFunc : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerFunc;
    AstCompilerFunc() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeBody;
};

struct AstCompilerShortFunc : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerShortFunc;
    AstCompilerShortFunc() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeExpr;
};

struct AstCompilerFuncExpr : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerFuncExpr;
    AstCompilerFuncExpr() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeExpr;
};

struct AstIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::Identifier;
    AstIdentifier() :
        AstNode(ID)
    {
    }

    TokenRef tokName;
};

struct AstScopedIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::ScopedIdentifier;
    AstScopedIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstUpIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::UpIdentifier;
    AstUpIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstPostfixIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::PostfixIdentifier;
    AstPostfixIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdent;
    AstNodeRef nodePostfix;
};

struct AstMultiPostfixIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::MultiPostfixIdentifier;
    AstMultiPostfixIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdent;
    AstNodeRef nodePostfixBlock;
};

struct AstFuncCall : AstNode
{
    static constexpr auto ID = AstNodeId::FuncCall;
    AstFuncCall() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstStructInit : AstNode
{
    static constexpr auto ID = AstNodeId::StructInit;
    AstStructInit() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstIndexExpr : AstNode
{
    static constexpr auto ID = AstNodeId::IndexExpr;
    AstIndexExpr() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstArgument : AstNode
{
    explicit AstArgument(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }
};

struct AstUnnamedArgument : AstArgument
{
    static constexpr auto ID = AstNodeId::UnnamedArgument;
    AstUnnamedArgument() :
        AstArgument(ID)
    {
    }
};

struct AstNamedArgument : AstArgument
{
    static constexpr auto ID = AstNodeId::NamedArgument;
    AstNamedArgument() :
        AstArgument(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeArg;
};

struct AstParenExpr : AstNode
{
    static constexpr auto ID = AstNodeId::ParenExpr;
    AstParenExpr() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
};

struct AstNamedArgumentList : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::NamedArgumentList;
    AstNamedArgumentList() :
        AstCompoundBase(ID)
    {
    }
};

struct AstUnnamedArgumentList : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::UnnamedArgumentList;
    AstUnnamedArgumentList() :
        AstCompoundBase(ID)
    {
    }
};

struct AstBinaryBase : AstNode
{
    explicit AstBinaryBase(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokOp;
    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstLogicalExpr : AstBinaryBase
{
    static constexpr auto ID = AstNodeId::LogicalExpr;
    AstLogicalExpr() :
        AstBinaryBase(ID)
    {
    }
};

struct AstRelationalExpr : AstBinaryBase
{
    static constexpr auto ID = AstNodeId::RelationalExpr;
    AstRelationalExpr() :
        AstBinaryBase(ID)
    {
    }
};

struct AstBinaryExpr : AstBinaryBase
{
    static constexpr auto ID = AstNodeId::BinaryExpr;
    AstBinaryExpr() :
        AstBinaryBase(ID)
    {
    }

    AstModifierFlags modifierFlags;
};

struct AstUnaryExpr : AstNode
{
    static constexpr auto ID = AstNodeId::UnaryExpr;
    AstUnaryExpr() :
        AstNode(ID)
    {
    }

    TokenRef   tokOp;
    AstNodeRef nodeExpr;
};

struct AstLiteralBase : AstNode
{
    explicit AstLiteralBase(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef tokValue;
};

struct AstIntegerLiteral : AstLiteralBase
{
    static constexpr auto ID = AstNodeId::IntegerLiteral;
    AstIntegerLiteral() :
        AstLiteralBase(ID)
    {
    }
};

struct AstFloatLiteral : AstLiteralBase
{
    static constexpr auto ID = AstNodeId::FloatLiteral;
    AstFloatLiteral() :
        AstLiteralBase(ID)
    {
    }
};

struct AstStringLiteral : AstLiteralBase
{
    static constexpr auto ID = AstNodeId::StringLiteral;
    AstStringLiteral() :
        AstLiteralBase(ID)
    {
    }
};

struct AstCharacterLiteral : AstLiteralBase
{
    static constexpr auto ID = AstNodeId::CharacterLiteral;
    AstCharacterLiteral() :
        AstLiteralBase(ID)
    {
    }
};

struct AstBoolLiteral : AstLiteralBase
{
    static constexpr auto ID = AstNodeId::BoolLiteral;
    AstBoolLiteral() :
        AstLiteralBase(ID)
    {
    }
};

struct AstNullLiteral : AstLiteralBase
{
    static constexpr auto ID = AstNodeId::NullLiteral;
    AstNullLiteral() :
        AstLiteralBase(ID)
    {
    }
};

struct AstCompilerLiteral : AstLiteralBase
{
    static constexpr auto ID = AstNodeId::CompilerLiteral;
    AstCompilerLiteral() :
        AstLiteralBase(ID)
    {
    }
};

struct AstSuffixedLiteral : AstNode
{
    static constexpr auto ID = AstNodeId::SuffixedLiteral;
    AstSuffixedLiteral() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeLiteral;
    AstNodeRef nodeQuote;
};

struct AstArrayLiteral : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::ArrayLiteral;
    AstArrayLiteral() :
        AstCompoundBase(ID)
    {
    }
};

struct AstScopeAccess : AstNode
{
    static constexpr auto ID = AstNodeId::ScopeAccess;
    AstScopeAccess() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstAsExpr : AstNode
{
    static constexpr auto ID = AstNodeId::AsExpr;
    AstAsExpr() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstIsExpr : AstNode
{
    static constexpr auto ID = AstNodeId::IsExpr;
    AstIsExpr() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstCastAutoExpr : AstNode
{
    static constexpr auto ID = AstNodeId::CastAutoExpr;
    AstCastAutoExpr() :
        AstNode(ID)
    {
    }

    TokenRef         tokOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExpr;
};

struct AstCastExpr : AstNode
{
    static constexpr auto ID = AstNodeId::CastExpr;
    AstCastExpr() :
        AstNode(ID)
    {
    }

    TokenRef         tokOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeType;
    AstNodeRef       nodeExpr;
};

struct AstEnumDecl : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::EnumDecl;
    AstEnumDecl() :
        AstCompoundBase(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeType;
};

struct AstEnumValue : AstNode
{
    static constexpr auto ID = AstNodeId::EnumValue;
    AstEnumValue() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeValue;
};

struct AstEnumUsingValue : AstNode
{
    static constexpr auto ID = AstNodeId::EnumUsingValue;
    AstEnumUsingValue() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeName;
};

struct AstEnumImplDecl : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::EnumImplDecl;
    AstEnumImplDecl() :
        AstCompoundBase(ID)
    {
    }

    AstNodeRef nodeName;
};

struct AstQualifiedType : AstNode
{
    static constexpr auto ID = AstNodeId::QualifiedType;
    AstQualifiedType() :
        AstNode(ID)
    {
    }

    TokenRef   tokQual;
    AstNodeRef nodeType;
};

struct AstLRefType : AstNode
{
    static constexpr auto ID = AstNodeId::LRefType;
    AstLRefType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstRRefType : AstNode
{
    static constexpr auto ID = AstNodeId::RRefType;
    AstRRefType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstPointerType : AstNode
{
    static constexpr auto ID = AstNodeId::PointerType;
    AstPointerType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstBlockPointerType : AstNode
{
    static constexpr auto ID = AstNodeId::BlockPointerType;
    AstBlockPointerType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstSliceType : AstNode
{
    static constexpr auto ID = AstNodeId::SliceType;
    AstSliceType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstIncompleteArrayType : AstNode
{
    static constexpr auto ID = AstNodeId::IncompleteArrayType;
    AstIncompleteArrayType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstArrayType : AstNode
{
    static constexpr auto ID = AstNodeId::ArrayType;
    AstArrayType() :
        AstNode(ID)
    {
    }

    SpanRef    spanDimensions;
    AstNodeRef nodePointeeType;
};

struct AstNamedType : AstNode
{
    static constexpr auto ID = AstNodeId::NamedType;
    AstNamedType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstBuiltinType : AstNode
{
    static constexpr auto ID = AstNodeId::BuiltinType;
    AstBuiltinType() :
        AstNode(ID)
    {
    }

    TokenRef tokType;
};

struct AstCompilerType : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerType;
    AstCompilerType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstCompilerIf : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::CompilerIf;
    AstCompilerIf() :
        AstCompoundBase(ID)
    {
    }

    TokenRef   tokIf;
    AstNodeRef nodeCondition;
    AstNodeRef nodeIfBlock;
    AstNodeRef nodeElseBlock;
};

struct AstCompilerElse : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::CompilerElse;
    AstCompilerElse() :
        AstCompoundBase(ID)
    {
    }
};

struct AstCompilerElseIf : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::CompilerElseIf;
    AstCompilerElseIf() :
        AstCompoundBase(ID)
    {
    }
};

struct AstAttribute : AstNode
{
    static constexpr auto ID = AstNodeId::Attribute;
    AstAttribute() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdent;
    AstNodeRef nodeArgs;
};

struct AstAttributeList : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::AttributeList;
    AstAttributeList() :
        AstCompoundBase(ID)
    {
    }

    AstNodeRef nodeBody;
};

struct AstDependenciesDecl : AstNode
{
    static constexpr auto ID = AstNodeId::DependenciesDecl;
    AstDependenciesDecl() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeBody;
};

struct AstUsingDecl : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::UsingDecl;
    AstUsingDecl() :
        AstCompoundBase(ID)
    {
    }
};

struct AstStructDeclBase : AstCompoundBase
{
    explicit AstStructDeclBase(AstNodeId nodeId) :
        AstCompoundBase(nodeId)
    {
    }

    TokenRef tokName;
    SpanRef  spanGenericParams;
    SpanRef  spanWhere;
};

struct AstStructDecl : AstStructDeclBase
{
    static constexpr auto ID = AstNodeId::StructDecl;
    AstStructDecl() :
        AstStructDeclBase(ID)
    {
    }
};

struct AstUnionDecl : AstStructDeclBase
{
    static constexpr auto ID = AstNodeId::UnionDecl;
    AstUnionDecl() :
        AstStructDeclBase(ID)
    {
    }
};

struct AstAccessModifier : AstNode
{
    static constexpr auto ID = AstNodeId::AccessModifier;
    AstAccessModifier() :
        AstNode(ID)
    {
    }

    TokenRef   tokAccess;
    AstNodeRef nodeWhat;
};

struct AstConstraintBlock : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::ConstraintBlock;
    AstConstraintBlock() :
        AstCompoundBase(ID)
    {
    }

    TokenRef tokConstraint;
};

struct AstConstraintExpr : AstNode
{
    static constexpr auto ID = AstNodeId::ConstraintExpr;
    AstConstraintExpr() :
        AstNode(ID)
    {
    }

    TokenRef   tokConstraint;
    AstNodeRef nodeExpr;
};

struct AstGenericParamsList : AstCompoundBase
{
    static constexpr auto ID = AstNodeId::GenericParamsList;
    AstGenericParamsList() :
        AstCompoundBase(ID)
    {
    }
};

struct AstGenericParamBase : AstNode
{
    explicit AstGenericParamBase(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeAssign;
};

struct AstGenericParamValue : AstGenericParamBase
{
    static constexpr auto ID = AstNodeId::GenericParamValue;
    AstGenericParamValue() :
        AstGenericParamBase(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstGenericParamType : AstGenericParamBase
{
    static constexpr auto ID = AstNodeId::GenericParamType;
    AstGenericParamType() :
        AstGenericParamBase(ID)
    {
    }
};
