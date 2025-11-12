// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNodeId.h"

SWC_BEGIN_NAMESPACE()

struct AstInvalid : AstNode
{
    static constexpr auto ID = AstNodeId::Invalid;
    AstInvalid() :
        AstNode(ID)
    {
    }
};

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

    SpanRef spanGlobals;
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

struct AstCompilerGlobal : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerGlobal;
    AstCompilerGlobal() :
        AstNode(ID)
    {
    }

    enum class Mode
    {
        Skip,
        SkipFmt,
        Generated,
        Export,
        AttributeList,
        AccessPublic,
        AccessInternal,
        Namespace,
        CompilerIf,
        Using,
    };

    Mode       mode;
    AstNodeRef nodeMode;
};

struct AstCompilerImport : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerImport;
    AstCompilerImport() :
        AstNode(ID)
    {
    }

    TokenRef tokModuleName;
    TokenRef tokLocation;
    TokenRef tokVersion;
};

struct AstCompilerScope : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerScope;
    AstCompilerScope() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeBody;
};

struct AstInternalCallZeroBase : AstNode
{
    explicit AstInternalCallZeroBase(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    TokenRef tokName;
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

struct AstIntrinsicCallZero : AstInternalCallZeroBase
{
    static constexpr auto ID = AstNodeId::IntrinsicCallZero;
    AstIntrinsicCallZero() :
        AstInternalCallZeroBase(ID)
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

struct AstCompilerCallUnary : AstInternalCallUnaryBase
{
    static constexpr auto ID = AstNodeId::CompilerCallUnary;
    AstCompilerCallUnary() :
        AstInternalCallUnaryBase(ID)
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

struct AstLambdaExpr : AstNode
{
    explicit AstLambdaExpr(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    AstNodeRef nodeParams;
    AstNodeRef nodeReturnType;
    AstNodeRef nodeBody;
};

struct AstFunctionExpr : AstLambdaExpr
{
    static constexpr auto ID = AstNodeId::FunctionExpr;
    AstFunctionExpr() :
        AstLambdaExpr(ID)
    {
    }
};

struct AstClosureExpr : AstLambdaExpr
{
    static constexpr auto ID = AstNodeId::ClosureExpr;
    AstClosureExpr() :
        AstLambdaExpr(ID)
    {
    }

    AstNodeRef nodeCaptureArgs;
};

struct AstFunctionDecl : AstNode
{
    static constexpr auto ID = AstNodeId::FunctionDecl;
    explicit AstFunctionDecl() :
        AstNode(ID)
    {
    }

    SpanRef    spanGenericParams;
    TokenRef   tokName;
    AstNodeRef nodeParams;
    AstNodeRef nodeReturnType;
    SpanRef    spanConstraints;
    AstNodeRef nodeBody;
};

struct AstInterfaceDecl : AstNode
{
    static constexpr auto ID = AstNodeId::InterfaceDecl;
    explicit AstInterfaceDecl() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeBody;
};

struct AstInterfaceBody : AstCompound
{
    static constexpr auto ID = AstNodeId::InterfaceBody;
    explicit AstInterfaceBody() :
        AstCompound(ID)
    {
    }
};

struct AstAttrDecl : AstNode
{
    static constexpr auto ID = AstNodeId::AttrDecl;
    explicit AstAttrDecl() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeParams;
};

struct AstFuncParamMe : AstNode
{
    static constexpr auto ID = AstNodeId::FuncParamMe;
    AstFuncParamMe() :
        AstNode(ID)
    {
    }

    enum class FlagsE : Flags
    {
        Zero  = 0,
        Const = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;
};

struct AstReturn : AstNode
{
    static constexpr auto ID = AstNodeId::Return;
    AstReturn() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
};

struct AstFunctionBody : AstCompound
{
    static constexpr auto ID = AstNodeId::FunctionBody;
    AstFunctionBody() :
        AstCompound(ID)
    {
    }
};

struct AstLambdaTypeParam : AstNode
{
    static constexpr auto ID = AstNodeId::LambdaTypeParam;
    AstLambdaTypeParam() :
        AstNode(ID)
    {
    }

    TokenRef   tokName;
    AstNodeRef nodeType;
    AstNodeRef nodeDefaultValue;
};

struct AstLambdaTypeParamList : AstCompound
{
    static constexpr auto ID = AstNodeId::LambdaTypeParamList;
    AstLambdaTypeParamList() :
        AstCompound(ID)
    {
    }
};

struct AstFunctionParamList : AstCompound
{
    static constexpr auto ID = AstNodeId::FunctionParamList;
    AstFunctionParamList() :
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

struct AstClosureCapture : AstCompound
{
    static constexpr auto ID = AstNodeId::ClosureCapture;
    AstClosureCapture() :
        AstCompound(ID)
    {
    }

    enum class FlagsE : Flags
    {
        Zero    = 0,
        Address = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;

    TokenRef tokName;
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

struct AstCompilerMessageFunc : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerMessageFunc;
    AstCompilerMessageFunc() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeParam;
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

struct AstMultiPostfixIdentifier : AstCompound
{
    static constexpr auto ID = AstNodeId::MultiPostfixIdentifier;
    AstMultiPostfixIdentifier() :
        AstCompound(ID)
    {
    }

    TokenRef tokName;
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
    AstNodeRef nodeArg;
};

struct AstMultiIndexExpr : AstCompound
{
    static constexpr auto ID = AstNodeId::MultiIndexExpr;
    AstMultiIndexExpr() :
        AstCompound(ID)
    {
    }

    AstNodeRef nodeExpr;
};

struct AstSlicingExpr : AstCompound
{
    static constexpr auto ID = AstNodeId::SlicingExpr;
    AstSlicingExpr() :
        AstCompound(ID)
    {
    }

    TokenRef   tokWhat;
    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
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

struct AstDeRefOp : AstNode
{
    static constexpr auto ID = AstNodeId::DeRefOp;
    AstDeRefOp() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
};

struct AstMoveRefOp : AstNode
{
    static constexpr auto ID = AstNodeId::MoveRefOp;
    AstMoveRefOp() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
};

struct AstBinaryConditionalOp : AstNode
{
    static constexpr auto ID = AstNodeId::BinaryConditionalOp;
    AstBinaryConditionalOp() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;
};

struct AstConditionalOp : AstNode
{
    static constexpr auto ID = AstNodeId::ConditionalOp;
    AstConditionalOp() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeCond;
    AstNodeRef nodeTrue;
    AstNodeRef nodeFalse;
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

struct AstCompilerTypeExpr : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerTypeExpr;
    AstCompilerTypeExpr() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstLambdaType : AstNode
{
    static constexpr auto ID = AstNodeId::LambdaType;
    explicit AstLambdaType() :
        AstNode(ID)
    {
    }

    enum class FlagsE : Flags
    {
        Zero    = 0,
        Mtd     = 1 << 0,
        Throw   = 1 << 1,
        Closure = 1 << 2,
        Const   = 1 << 3,
        Impl    = 1 << 4,
    };
    using Flags = EnumFlags<FlagsE>;

    AstNodeRef nodeParams;
    AstNodeRef nodeReturnType;
};

struct AstRetValType : AstNode
{
    static constexpr auto ID = AstNodeId::RetValType;
    AstRetValType() :
        AstNode(ID)
    {
    }
};

struct AstCodeType : AstNode
{
    static constexpr auto ID = AstNodeId::CodeType;
    AstCodeType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstVariadicType : AstNode
{
    static constexpr auto ID = AstNodeId::VariadicType;
    AstVariadicType() :
        AstNode(ID)
    {
    }
};

struct AstTypedVariadicType : AstNode
{
    static constexpr auto ID = AstNodeId::TypedVariadicType;
    AstTypedVariadicType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstCompilerIf : AstCompound
{
    static constexpr auto ID = AstNodeId::CompilerIf;
    AstCompilerIf() :
        AstCompound(ID)
    {
    }

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

struct AstTopLevelCall : AstNode
{
    static constexpr auto ID = AstNodeId::TopLevelCall;
    AstTopLevelCall() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeIdentifier;
    AstNodeRef nodeArgs;
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

    enum class FlagsE : Flags
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

struct AstVarMultiNameDecl : AstNode
{
    static constexpr auto ID = AstNodeId::VarMultiNameDecl;
    AstVarMultiNameDecl() :
        AstNode(ID)
    {
    }

    SpanRef    tokNames;
    AstNodeRef nodeType;
    AstNodeRef nodeInit;
};

struct AstVarMultiDecl : AstCompound
{
    static constexpr auto ID = AstNodeId::VarMultiDecl;
    AstVarMultiDecl() :
        AstCompound(ID)
    {
    }
};

struct AstDecompositionDecl : AstNode
{
    static constexpr auto ID = AstNodeId::DecompositionDecl;
    AstDecompositionDecl() :
        AstNode(ID)
    {
    }

    SpanRef    spanNames;
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

struct AstUnreachable : AstNode
{
    static constexpr auto ID = AstNodeId::Unreachable;
    AstUnreachable() :
        AstNode(ID)
    {
    }
};

struct AstContinue : AstNode
{
    static constexpr auto ID = AstNodeId::Continue;
    AstContinue() :
        AstNode(ID)
    {
    }
};

struct AstBreak : AstNode
{
    static constexpr auto ID = AstNodeId::Break;
    AstBreak() :
        AstNode(ID)
    {
    }
};

struct AstScopedBreak : AstNode
{
    static constexpr auto ID = AstNodeId::ScopedBreak;
    AstScopedBreak() :
        AstNode(ID)
    {
    }

    TokenRef tokName;
};

struct AstFallThrough : AstNode
{
    static constexpr auto ID = AstNodeId::FallThrough;
    AstFallThrough() :
        AstNode(ID)
    {
    }
};

struct AstDeferDecl : AstNode
{
    static constexpr auto ID = AstNodeId::DeferDecl;
    AstDeferDecl() :
        AstNode(ID)
    {
    }

    AstModifierFlags modifierFlags;
    AstNodeRef       nodeBody;
};

struct AstIfBase : AstCompound
{
    explicit AstIfBase(AstNodeId nodeId) :
        AstCompound(nodeId)
    {
    }

    AstNodeRef nodeIfBlock;
    AstNodeRef nodeElseBlock;
};

struct AstIf : AstIfBase
{
    static constexpr auto ID = AstNodeId::If;
    AstIf() :
        AstIfBase(ID)
    {
    }

    AstNodeRef nodeCondition;
};

struct AstVarIf : AstIfBase
{
    static constexpr auto ID = AstNodeId::VarIf;
    AstVarIf() :
        AstIfBase(ID)
    {
    }

    AstNodeRef nodeVar;
    AstNodeRef nodeWhere;
};

struct AstElse : AstCompound
{
    static constexpr auto ID = AstNodeId::Else;
    AstElse() :
        AstCompound(ID)
    {
    }
};

struct AstElseIf : AstCompound
{
    static constexpr auto ID = AstNodeId::ElseIf;
    AstElseIf() :
        AstCompound(ID)
    {
    }
};

struct AstWith : AstNode
{
    static constexpr auto ID = AstNodeId::With;
    AstWith() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeBody;
};

struct AstVarWith : AstNode
{
    static constexpr auto ID = AstNodeId::VarWith;
    AstVarWith() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeVar;
    AstNodeRef nodeBody;
};

struct AstIntrinsicInitDropCopyMove : AstNode
{
    explicit AstIntrinsicInitDropCopyMove(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    AstNodeRef nodeWhat;
    AstNodeRef nodeCount;
};

struct AstIntrinsicInit : AstIntrinsicInitDropCopyMove
{
    static constexpr auto ID = AstNodeId::IntrinsicInit;
    explicit AstIntrinsicInit() :
        AstIntrinsicInitDropCopyMove(ID)
    {
    }

    SpanRef spanArgs;
};

struct AstIntrinsicDrop : AstIntrinsicInitDropCopyMove
{
    static constexpr auto ID = AstNodeId::IntrinsicDrop;
    explicit AstIntrinsicDrop() :
        AstIntrinsicInitDropCopyMove(ID)
    {
    }
};

struct AstIntrinsicPostCopy : AstIntrinsicInitDropCopyMove
{
    static constexpr auto ID = AstNodeId::IntrinsicPostCopy;
    explicit AstIntrinsicPostCopy() :
        AstIntrinsicInitDropCopyMove(ID)
    {
    }
};

struct AstIntrinsicPostMove : AstIntrinsicInitDropCopyMove
{
    static constexpr auto ID = AstNodeId::IntrinsicPostMove;
    explicit AstIntrinsicPostMove() :
        AstIntrinsicInitDropCopyMove(ID)
    {
    }
};

struct AstWhile : AstNode
{
    static constexpr auto ID = AstNodeId::While;
    explicit AstWhile() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
    AstNodeRef nodeBody;
};

struct AstForeach : AstNode
{
    static constexpr auto ID = AstNodeId::Foreach;
    explicit AstForeach() :
        AstNode(ID)
    {
    }

    enum class FlagsE : Flags
    {
        Zero      = 0,
        ByAddress = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;

    TokenRef         tokSpecialization;
    AstModifierFlags modifierFlags;
    SpanRef          spanNames;
    AstNodeRef       nodeExpr;
    AstNodeRef       nodeWhere;
    AstNodeRef       nodeBody;
};

//========================================================================================
//========================================================================================

template<AstNodeId ID>
struct AstTypeOf;

#define SWC_NODE_DEF(E)            \
    template<>                     \
    struct AstTypeOf<AstNodeId::E> \
    {                              \
        using type = Ast##E;       \
    };
#include "AstNodes.inc"
#undef SWC_NODE_DEF

template<class F>
decltype(auto) visitAstNodeId(AstNodeId id, F f)
{
    switch (id)
    {
#define SWC_NODE_DEF(E) \
    case AstNodeId::E:  \
        return std::forward<F>(f).operator()<AstNodeId::E>();
#include "AstNodes.inc"

#undef SWC_NODE_DEF
        default:
            SWC_UNREACHABLE();
    }
};

struct AstNodeIdInfo
{
    std::string_view name;

    using CollectFunc = void (*)(const AstNode*, SmallVector<AstNodeRef>&);
    CollectFunc collect;
};

// Helper template to call collect on any node type
template<AstNodeId ID>
void collectChildren(const AstNode* node, SmallVector<AstNodeRef>& out)
{
    using NodeType = AstTypeOf<ID>::type;
    castAst<NodeType>(node)->collectChildren(out);
}

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_DEF(enum) AstNodeIdInfo{#enum, &collectChildren<AstNodeId::enum>},
#include "AstNodes.inc"

#undef SWC_NODE_DEF
};

SWC_END_NAMESPACE()
