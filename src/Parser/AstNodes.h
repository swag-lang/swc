// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/Types.h"

struct AstCompound : AstNode
{
    explicit AstCompound(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    SpanRef spanChildren;
};

struct AstFile : AstCompound
{
    static constexpr auto ID = AstNodeId::File;
    AstFile() :
        AstCompound(ID)
    {
    }
};

struct AstTopLevelBlock : AstCompound
{
    static constexpr auto ID = AstNodeId::TopLevelBlock;
    AstTopLevelBlock() :
        AstCompound(ID)
    {
    }
};

struct AstEmbeddedBlock : AstCompound
{
    static constexpr auto ID = AstNodeId::EmbeddedBlock;
    AstEmbeddedBlock() :
        AstCompound(ID)
    {
    }
};

struct AstImpl : AstCompound
{
    static constexpr auto ID = AstNodeId::Impl;
    AstImpl() :
        AstCompound(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstImplFor : AstCompound
{
    static constexpr auto ID = AstNodeId::ImplFor;
    AstImplFor() :
        AstCompound(ID)
    {
    }

    AstNodeRef nodeIdent;
    AstNodeRef nodeFor;
};

struct AstNamespace : AstNode
{
    static constexpr auto ID = AstNodeId::Namespace;
    AstNamespace() :
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

struct AstInternalCallUnaryBase : AstNode
{
    explicit AstInternalCallUnaryBase(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeArg1;
};

struct AstInternalCallBinaryBase : AstNode
{
    explicit AstInternalCallBinaryBase(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeArg1;
    AstNodeRef nodeArg2;
};

struct AstInternalCallTernaryBase : AstNode
{
    explicit AstInternalCallTernaryBase(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeArg1;
    AstNodeRef nodeArg2;
    AstNodeRef nodeArg3;
};

struct AstCompilerCallUnary : AstInternalCallUnaryBase
{
    static constexpr auto ID = AstNodeId::CompilerCallUnary;
    AstCompilerCallUnary() :
        AstInternalCallUnaryBase(ID)
    {
    }
};

struct AstIntrinsicCallUnary : AstInternalCallUnaryBase
{
    static constexpr auto ID = AstNodeId::IntrinsicCallUnary;
    AstIntrinsicCallUnary() :
        AstInternalCallUnaryBase(ID)
    {
    }
};

struct AstIntrinsicCallBinary : AstInternalCallBinaryBase
{
    static constexpr auto ID = AstNodeId::IntrinsicCallBinary;
    AstIntrinsicCallBinary() :
        AstInternalCallBinaryBase(ID)
    {
    }
};

struct AstIntrinsicCallTernary : AstInternalCallTernaryBase
{
    static constexpr auto ID = AstNodeId::IntrinsicCallTernary;
    AstIntrinsicCallTernary() :
        AstInternalCallTernaryBase(ID)
    {
    }
};

struct AstIntrinsicValue : AstNode
{
    static constexpr auto ID = AstNodeId::IntrinsicValue;
    AstIntrinsicValue() :
        AstNode(ID)
    {
    }

    TokenRef tokName;
};

struct AstFuncBody : AstCompound
{
    static constexpr auto ID = AstNodeId::FuncBody;
    AstFuncBody() :
        AstCompound(ID)
    {
    }
};

struct AstFuncParam : AstNode
{
    static constexpr auto ID = AstNodeId::FuncParam;
    AstFuncParam() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeType;
    AstNodeRef nodeDefaultValue;
};

struct AstLambdaParameterList : AstCompound
{
    static constexpr auto ID = AstNodeId::LambdaParameterList;
    AstLambdaParameterList() :
        AstCompound(ID)
    {
    }
};

struct AstClosureCaptureList : AstCompound
{
    static constexpr auto ID = AstNodeId::ClosureCaptureList;
    AstClosureCaptureList() :
        AstCompound(ID)
    {
    }
};

struct AstCompilerAssert : AstInternalCallUnaryBase
{
    static constexpr auto ID = AstNodeId::CompilerAssert;
    AstCompilerAssert() :
        AstInternalCallUnaryBase(ID)
    {
    }
};

struct AstCompilerError : AstInternalCallUnaryBase
{
    static constexpr auto ID = AstNodeId::CompilerError;
    AstCompilerError() :
        AstInternalCallUnaryBase(ID)
    {
    }
};

struct AstCompilerWarning : AstInternalCallUnaryBase
{
    static constexpr auto ID = AstNodeId::CompilerWarning;
    AstCompilerWarning() :
        AstInternalCallUnaryBase(ID)
    {
    }
};

struct AstCompilerPrint : AstInternalCallUnaryBase
{
    static constexpr auto ID = AstNodeId::CompilerPrint;
    AstCompilerPrint() :
        AstInternalCallUnaryBase(ID)
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

struct AstCompilerEmbeddedFunc : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerEmbeddedFunc;
    AstCompilerEmbeddedFunc() :
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
    AstNodeRef nodeBody;
};

struct AstCompilerExpr : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerExpr;
    AstCompilerExpr() :
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

struct AstPreQualifiedIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::PreQualifiedIdentifier;
    AstPreQualifiedIdentifier() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdent;
};

struct AstAncestorIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::AncestorIdentifier;
    AstAncestorIdentifier() :
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

    TokenRef   tokName;
    AstNodeRef nodePostfix;
};

struct AstMultiPostfixIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::MultiPostfixIdentifier;
    AstMultiPostfixIdentifier() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodePostfixBlock;
};

struct AstCall : AstNode
{
    static constexpr auto ID = AstNodeId::Call;
    AstCall() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeArgs;
};

struct AstStructInitializerList : AstNode
{
    static constexpr auto ID = AstNodeId::StructInitializerList;
    AstStructInitializerList() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeWhat;
    SpanRef    spanArgs;
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

struct AstNamedArgList : AstCompound
{
    static constexpr auto ID = AstNodeId::NamedArgList;
    AstNamedArgList() :
        AstCompound(ID)
    {
    }
};

struct AstUnnamedArgList : AstCompound
{
    static constexpr auto ID = AstNodeId::UnnamedArgList;
    AstUnnamedArgList() :
        AstCompound(ID)
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

struct AstInitializerExpr : AstNode
{
    static constexpr auto ID = AstNodeId::InitializerExpr;
    AstInitializerExpr() :
        AstNode(ID)
    {
    }

    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExpr;
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

struct AstPostfixedLiteral : AstNode
{
    static constexpr auto ID = AstNodeId::PostfixedLiteral;
    AstPostfixedLiteral() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeLiteral;
    AstNodeRef nodeQuote;
};

struct AstArrayLiteral : AstCompound
{
    static constexpr auto ID = AstNodeId::ArrayLiteral;
    AstArrayLiteral() :
        AstCompound(ID)
    {
    }
};

struct AstStructLiteral : AstCompound
{
    static constexpr auto ID = AstNodeId::StructLiteral;
    AstStructLiteral() :
        AstCompound(ID)
    {
    }
};

struct AstScopeResolution : AstNode
{
    static constexpr auto ID = AstNodeId::ScopeResolution;
    AstScopeResolution() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstAsCastExpr : AstNode
{
    static constexpr auto ID = AstNodeId::AsCastExpr;
    AstAsCastExpr() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstIsTypeExpr : AstNode
{
    static constexpr auto ID = AstNodeId::IsTypeExpr;
    AstIsTypeExpr() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeType;
};

struct AstAutoCastExpr : AstNode
{
    static constexpr auto ID = AstNodeId::AutoCastExpr;
    AstAutoCastExpr() :
        AstNode(ID)
    {
    }

    TokenRef         tokOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExpr;
};

struct AstExplicitCastExpr : AstNode
{
    static constexpr auto ID = AstNodeId::ExplicitCastExpr;
    AstExplicitCastExpr() :
        AstNode(ID)
    {
    }

    TokenRef         tokOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeType;
    AstNodeRef       nodeExpr;
};

struct AstEnumDecl : AstCompound
{
    static constexpr auto ID = AstNodeId::EnumDecl;
    AstEnumDecl() :
        AstCompound(ID)
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

struct AstEnumUse : AstNode
{
    static constexpr auto ID = AstNodeId::EnumUse;
    AstEnumUse() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeName;
};

struct AstImplEnum : AstCompound
{
    static constexpr auto ID = AstNodeId::ImplEnum;
    AstImplEnum() :
        AstCompound(ID)
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

struct AstLambdaType : AstNode
{
    explicit AstLambdaType(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    enum class FlagsE : Flags
    {
        Zero  = 0,
        Mtd   = 1 << 0,
        Throw = 1 << 1,
    };
    using Flags = EnumFlags<FlagsE>;

    SpanRef    nodeParams;
    AstNodeRef nodeReturnType;
};

struct AstFunctionType : AstLambdaType
{
    static constexpr auto ID = AstNodeId::FunctionType;
    AstFunctionType() :
        AstLambdaType(ID)
    {
    }
};

struct AstClosureType : AstLambdaType
{
    static constexpr auto ID = AstNodeId::ClosureType;
    AstClosureType() :
        AstLambdaType(ID)
    {
    }

    SpanRef nodeCaptureParams;
};

struct AstRetValType : AstNode
{
    static constexpr auto ID = AstNodeId::RetValType;
    AstRetValType() :
        AstNode(ID)
    {
    }
};

struct AstCompilerIf : AstCompound
{
    static constexpr auto ID = AstNodeId::CompilerIf;
    AstCompilerIf() :
        AstCompound(ID)
    {
    }

    TokenRef   tokIf;
    AstNodeRef nodeCondition;
    AstNodeRef nodeIfBlock;
    AstNodeRef nodeElseBlock;
};

struct AstCompilerElse : AstCompound
{
    static constexpr auto ID = AstNodeId::CompilerElse;
    AstCompilerElse() :
        AstCompound(ID)
    {
    }
};

struct AstCompilerElseIf : AstCompound
{
    static constexpr auto ID = AstNodeId::CompilerElseIf;
    AstCompilerElseIf() :
        AstCompound(ID)
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

struct AstAttributeList : AstCompound
{
    static constexpr auto ID = AstNodeId::AttributeList;
    AstAttributeList() :
        AstCompound(ID)
    {
    }

    AstNodeRef nodeBody;
};

struct AstDependencies : AstNode
{
    static constexpr auto ID = AstNodeId::Dependencies;
    AstDependencies() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeBody;
};

struct AstUsingDecl : AstCompound
{
    static constexpr auto ID = AstNodeId::UsingDecl;
    AstUsingDecl() :
        AstCompound(ID)
    {
    }
};

struct AstAggregateDecl : AstNode
{
    explicit AstAggregateDecl(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef   tokName;
    SpanRef    spanGenericParams;
    SpanRef    spanWhere;
    AstNodeRef nodeBody;
};

struct AstStructDecl : AstAggregateDecl
{
    static constexpr auto ID = AstNodeId::StructDecl;
    AstStructDecl() :
        AstAggregateDecl(ID)
    {
    }
};

struct AstUnionDecl : AstAggregateDecl
{
    static constexpr auto ID = AstNodeId::UnionDecl;
    AstUnionDecl() :
        AstAggregateDecl(ID)
    {
    }
};

struct AstAnonymousAggregateDecl : AstNode
{
    explicit AstAnonymousAggregateDecl(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    AstNodeRef nodeBody;
};

struct AstAnonymousStructDecl : AstAnonymousAggregateDecl
{
    static constexpr auto ID = AstNodeId::AnonymousStructDecl;
    AstAnonymousStructDecl() :
        AstAnonymousAggregateDecl(ID)
    {
    }
};

struct AstAnonymousUnionDecl : AstAnonymousAggregateDecl
{
    static constexpr auto ID = AstNodeId::AnonymousUnionDecl;
    AstAnonymousUnionDecl() :
        AstAnonymousAggregateDecl(ID)
    {
    }
};

struct AstAggregateBody : AstCompound
{
    static constexpr auto ID = AstNodeId::AggregateBody;
    AstAggregateBody() :
        AstCompound(ID)
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

struct AstConstraintBlock : AstCompound
{
    static constexpr auto ID = AstNodeId::ConstraintBlock;
    AstConstraintBlock() :
        AstCompound(ID)
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

struct AstGenericParamList : AstCompound
{
    static constexpr auto ID = AstNodeId::GenericParamList;
    AstGenericParamList() :
        AstCompound(ID)
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

struct AstGenericValueParam : AstGenericParamBase
{
    static constexpr auto ID = AstNodeId::GenericValueParam;
    AstGenericValueParam() :
        AstGenericParamBase(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstGenericTypeParam : AstGenericParamBase
{
    static constexpr auto ID = AstNodeId::GenericTypeParam;
    AstGenericTypeParam() :
        AstGenericParamBase(ID)
    {
    }
};

struct AstVarDecl : AstNode
{
    static constexpr auto ID = AstNodeId::VarDecl;
    AstVarDecl() :
        AstNode(ID)
    {
    }

    enum class FlagsE : AstNode::Flags
    {
        Zero  = 0,
        Var   = 1 << 0,
        Const = 1 << 1,
        Let   = 1 << 2,
    };
    using Flags = EnumFlags<FlagsE>;

    TokenRef   tokName;
    AstNodeRef nodeType;
    AstNodeRef nodeInit;
};

struct AstMultiVarDecl : AstNode
{
    static constexpr auto ID = AstNodeId::MultiVarDecl;
    AstMultiVarDecl() :
        AstNode(ID)
    {
    }

    SpanRef    tokNames;
    AstNodeRef nodeType;
    AstNodeRef nodeInit;
};

struct AstUndefined : AstNode
{
    static constexpr auto ID = AstNodeId::Undefined;
    AstUndefined() :
        AstNode(ID)
    {
    }
};

struct AstUsingVarDecl : AstNode
{
    static constexpr auto ID = AstNodeId::UsingVarDecl;
    AstUsingVarDecl() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeVar;
};

struct AstAlias : AstNode
{
    static constexpr auto ID = AstNodeId::Alias;
    AstAlias() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeExpr;
};

struct AstTryCatchAssumeExpr : AstNode
{
    static constexpr auto ID = AstNodeId::TryCatchAssumeExpr;
    AstTryCatchAssumeExpr() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeExpr;
};
