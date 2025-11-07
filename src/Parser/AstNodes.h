// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/Types.h"

struct AstCompoundBase : AstNodeBase
{
    explicit AstCompoundBase(AstNodeId nodeId) :
        AstNodeBase(nodeId)
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

struct AstNamespaceBlock : AstNodeBase
{
    static constexpr auto ID = AstNodeId::NamespaceBlock;
    AstNamespaceBlock() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeName;
    AstNodeRef nodeBody;
};

struct AstUsingNamespace : AstNodeBase
{
    static constexpr auto ID = AstNodeId::UsingNamespace;
    AstUsingNamespace() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeNamespace;
};

struct AstCall1Base : AstNodeBase
{
    explicit AstCall1Base(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
};

struct AstCall2Base : AstNodeBase
{
    explicit AstCall2Base(AstNodeId nodeId) :
        AstNodeBase(nodeId)
    {
    }

    TokenRef   tokRef;
    AstNodeRef nodeParam1;
    AstNodeRef nodeParam2;
};

struct AstCall3Base : AstNodeBase
{
    explicit AstCall3Base(AstNodeId nodeId) :
        AstNodeBase(nodeId)
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

struct AstCompilerFunc : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CompilerFunc;
    AstCompilerFunc() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeBody;
};

struct AstCompilerShortFunc : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CompilerShortFunc;
    AstCompilerShortFunc() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeExpr;
};

struct AstCompilerFuncExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CompilerFuncExpr;
    AstCompilerFuncExpr() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeExpr;
};

struct AstIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::Identifier;
    AstIdentifier() :
        AstNodeBase(ID)
    {
    }

    TokenRef tokName;
};

struct AstScopedIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ScopedIdentifier;
    AstScopedIdentifier() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstUpIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::UpIdentifier;
    AstUpIdentifier() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstPostfixIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::PostfixIdentifier;
    AstPostfixIdentifier() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdent;
    AstNodeRef nodePostfix;
};

struct AstMultiPostfixIdentifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::MultiPostfixIdentifier;
    AstMultiPostfixIdentifier() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdent;
    AstNodeRef nodePostfixBlock;
};

struct AstFuncCall : AstNodeBase
{
    static constexpr auto ID = AstNodeId::FuncCall;
    AstFuncCall() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstStructInit : AstNodeBase
{
    static constexpr auto ID = AstNodeId::StructInit;
    AstStructInit() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstIndexExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::IndexExpr;
    AstIndexExpr() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstArgument : AstNodeBase
{
    explicit AstArgument(AstNodeId nodeId) :
        AstNodeBase(nodeId)
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

struct AstParenExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ParenExpr;
    AstParenExpr() :
        AstNodeBase(ID)
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

struct AstBinaryBase : AstNodeBase
{
    explicit AstBinaryBase(AstNodeId nodeId) :
        AstNodeBase(nodeId)
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

struct AstUnaryExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::UnaryExpr;
    AstUnaryExpr() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tokOp;
    AstNodeRef nodeExpr;
};

struct AstLiteralBase : AstNodeBase
{
    explicit AstLiteralBase(AstNodeId nodeId) :
        AstNodeBase(nodeId)
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

struct AstSuffixedLiteral : AstNodeBase
{
    static constexpr auto ID = AstNodeId::SuffixedLiteral;
    AstSuffixedLiteral() :
        AstNodeBase(ID)
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

struct AstScopeAccess : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ScopeAccess;
    AstScopeAccess() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstAsExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::AsExpr;
    AstAsExpr() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstIsExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::IsExpr;
    AstIsExpr() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstCastAutoExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CastAutoExpr;
    AstCastAutoExpr() :
        AstNodeBase(ID)
    {
    }

    TokenRef         tokOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExpr;
};

struct AstCastExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CastExpr;
    AstCastExpr() :
        AstNodeBase(ID)
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

struct AstEnumValue : AstNodeBase
{
    static constexpr auto ID = AstNodeId::EnumValue;
    AstEnumValue() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeValue;
};

struct AstEnumUsingValue : AstNodeBase
{
    static constexpr auto ID = AstNodeId::EnumUsingValue;
    AstEnumUsingValue() :
        AstNodeBase(ID)
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

struct AstQualifiedType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::QualifiedType;
    AstQualifiedType() :
        AstNodeBase(ID)
    {
    }

    TokenRef   tokQual;
    AstNodeRef nodeType;
};

struct AstLRefType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::LRefType;
    AstLRefType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstRRefType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::RRefType;
    AstRRefType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstPointerType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::PointerType;
    AstPointerType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstBlockPointerType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::BlockPointerType;
    AstBlockPointerType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstSliceType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::SliceType;
    AstSliceType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstIncompleteArrayType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::IncompleteArrayType;
    AstIncompleteArrayType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstArrayType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ArrayType;
    AstArrayType() :
        AstNodeBase(ID)
    {
    }

    SpanRef    spanDimensions;
    AstNodeRef nodePointeeType;
};

struct AstNamedType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::NamedType;
    AstNamedType() :
        AstNodeBase(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstBuiltinType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::BuiltinType;
    AstBuiltinType() :
        AstNodeBase(ID)
    {
    }

    TokenRef tokType;
};

struct AstCompilerType : AstNodeBase
{
    static constexpr auto ID = AstNodeId::CompilerType;
    AstCompilerType() :
        AstNodeBase(ID)
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

struct AstAttribute : AstNodeBase
{
    static constexpr auto ID = AstNodeId::Attribute;
    AstAttribute() :
        AstNodeBase(ID)
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

struct AstDependenciesDecl : AstNodeBase
{
    static constexpr auto ID = AstNodeId::DependenciesDecl;
    AstDependenciesDecl() :
        AstNodeBase(ID)
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

struct AstAccessModifier : AstNodeBase
{
    static constexpr auto ID = AstNodeId::AccessModifier;
    AstAccessModifier() :
        AstNodeBase(ID)
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

struct AstConstraintExpr : AstNodeBase
{
    static constexpr auto ID = AstNodeId::ConstraintExpr;
    AstConstraintExpr() :
        AstNodeBase(ID)
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

struct AstGenericParamBase : AstNodeBase
{
    explicit AstGenericParamBase(AstNodeId nodeId) :
        AstNodeBase(nodeId)
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
