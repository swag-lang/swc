#pragma once

struct AstInvalid : AstNodeT<AstNodeId::Invalid>
{
};

struct AstFile : AstCompoundT<AstNodeId::File>
{
    SpanRef spanGlobals;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, ast, spanGlobals);
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstTopLevelBlock : AstCompoundT<AstNodeId::TopLevelBlock>
{
};

struct AstEmbeddedBlock : AstCompoundT<AstNodeId::EmbeddedBlock>
{
};

struct AstImpl : AstCompoundT<AstNodeId::Impl>
{
    AstNodeRef nodeIdent;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeIdent});
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstImplFor : AstCompoundT<AstNodeId::ImplFor>
{
    AstNodeRef nodeIdent;
    AstNodeRef nodeFor;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeIdent, nodeFor});
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstNamespace : AstCompoundT<AstNodeId::Namespace>
{
    AstNodeRef nodeName;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeName});
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstUsingNamespace : AstNodeT<AstNodeId::UsingNamespace>
{
    AstNodeRef nodeName;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeName});
    }
};

struct AstCompilerGlobal : AstNodeT<AstNodeId::CompilerGlobal>
{
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

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeMode});
    }
};

struct AstCompilerImport : AstNodeT<AstNodeId::CompilerImport>
{
    TokenRef tokModuleName;
    TokenRef tokLocation;
    TokenRef tokVersion;
};

struct AstCompilerScope : AstNodeT<AstNodeId::CompilerScope>
{
    TokenRef   tokName;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstInternalCallZero : AstNodeT<AstNodeId::InternalCallZero>
{
    TokenRef tokName;
};

struct AstInternalCallUnary : AstNodeT<AstNodeId::InternalCallUnary>
{
    TokenRef   tokName;
    AstNodeRef nodeArg1;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeArg1});
    }
};

struct AstInternalCallBinary : AstNodeT<AstNodeId::InternalCallBinary>
{
    TokenRef   tokName;
    AstNodeRef nodeArg1;
    AstNodeRef nodeArg2;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeArg1, nodeArg2});
    }
};

struct AstInternalCallTernary : AstNodeT<AstNodeId::InternalCallTernary>
{
    TokenRef   tokName;
    AstNodeRef nodeArg1;
    AstNodeRef nodeArg2;
    AstNodeRef nodeArg3;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeArg1, nodeArg2, nodeArg3});
    }
};

struct AstInternalCallVariadic : AstCompoundT<AstNodeId::InternalCallVariadic>
{
    TokenRef tokName;
};

struct AstIntrinsicValue : AstNodeT<AstNodeId::IntrinsicValue>
{
    TokenRef tokName;
};

struct AstFunctionExpr : AstLambdaExprT<AstNodeId::FunctionExpr>
{
};

struct AstClosureExpr : AstLambdaExprT<AstNodeId::ClosureExpr>
{
    SpanRef nodeCaptureArgs;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, ast, nodeCaptureArgs);
        AstLambdaExprT::collectChildren(out, ast);
    }
};

struct AstFunctionDecl : AstNodeT<AstNodeId::FunctionDecl>
{
    SpanRef    spanGenericParams;
    TokenRef   tokName;
    AstNodeRef nodeParams;
    AstNodeRef nodeReturnType;
    SpanRef    spanConstraints;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, ast, spanGenericParams);
        AstNode::collectChildren(out, {nodeParams, nodeReturnType});
        AstNode::collectChildren(out, ast, spanConstraints);
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstInterfaceDecl : AstNodeT<AstNodeId::InterfaceDecl>
{
    TokenRef   tokName;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstInterfaceBody : AstCompoundT<AstNodeId::InterfaceBody>
{
};

struct AstAttrDecl : AstNodeT<AstNodeId::AttrDecl>
{
    TokenRef   tokName;
    AstNodeRef nodeParams;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeParams});
    }
};

struct AstFuncParamMe : AstNodeT<AstNodeId::FuncParamMe>
{
    enum class FlagsE : Flags
    {
        Zero  = 0,
        Const = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;
};

struct AstReturn : AstNodeT<AstNodeId::Return>
{
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstFunctionBody : AstCompoundT<AstNodeId::FunctionBody>
{
};

struct AstLambdaTypeParam : AstNodeT<AstNodeId::LambdaTypeParam>
{
    TokenRef   tokName;
    AstNodeRef nodeType;
    AstNodeRef nodeDefaultValue;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType, nodeDefaultValue});
    }
};

struct AstFunctionParamList : AstCompoundT<AstNodeId::FunctionParamList>
{
};

struct AstClosureCapture : AstNodeT<AstNodeId::ClosureCapture>
{
    enum class FlagsE : Flags
    {
        Zero    = 0,
        Address = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;

    AstNodeRef nodeIdentifier;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeIdentifier});
    }
};

struct AstCompilerFunc : AstNodeT<AstNodeId::CompilerFunc>
{
    TokenRef   tokName;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstCompilerMessageFunc : AstNodeT<AstNodeId::CompilerMessageFunc>
{
    AstNodeRef nodeParam;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeParam, nodeBody});
    }
};

struct AstCompilerEmbeddedFunc : AstNodeT<AstNodeId::CompilerEmbeddedFunc>
{
    TokenRef   tokName;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstCompilerShortFunc : AstNodeT<AstNodeId::CompilerShortFunc>
{
    TokenRef   tokName;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstCompilerExpr : AstNodeT<AstNodeId::CompilerExpr>
{
    TokenRef   tokName;
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstIdentifier : AstNodeT<AstNodeId::Identifier>
{
    TokenRef tokName;
};

struct AstPreQualifiedIdentifier : AstNodeT<AstNodeId::PreQualifiedIdentifier>
{
    AstNodeRef nodeIdent;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeIdent});
    }
};

struct AstAncestorIdentifier : AstNodeT<AstNodeId::AncestorIdentifier>
{
    AstNodeRef nodeValue;
    AstNodeRef nodeIdent;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeValue, nodeIdent});
    }
};

struct AstSuffixIdentifier : AstNodeT<AstNodeId::SuffixIdentifier>
{
    TokenRef   tokName;
    AstNodeRef nodeSuffix;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeSuffix});
    }
};

struct AstMultiSuffixIdentifier : AstCompoundT<AstNodeId::MultiSuffixIdentifier>
{
    TokenRef tokName;
};

struct AstCall : AstCompoundT<AstNodeId::Call>
{
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeExpr});
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstAliasCall : AstCompoundT<AstNodeId::AliasCall>
{
    AstNodeRef nodeExpr;
    SpanRef    spanAliases;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeExpr});
        AstNode::collectChildren(out, ast, spanAliases);
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstStructInitializerList : AstNodeT<AstNodeId::StructInitializerList>
{
    AstNodeRef nodeWhat;
    SpanRef    spanArgs;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeWhat});
        AstNode::collectChildren(out, ast, spanArgs);
    }
};

struct AstIndexExpr : AstNodeT<AstNodeId::IndexExpr>
{
    AstNodeRef nodeExpr;
    AstNodeRef nodeArg;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr, nodeArg});
    }
};

struct AstMultiIndexExpr : AstCompoundT<AstNodeId::MultiIndexExpr>
{
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeExpr});
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstUnnamedArgument : AstNodeT<AstNodeId::UnnamedArgument>
{
};

struct AstNamedArgument : AstNodeT<AstNodeId::NamedArgument>
{
    TokenRef   tokName;
    AstNodeRef nodeArg;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeArg});
    }
};

struct AstParenExpr : AstNodeT<AstNodeId::ParenExpr>
{
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstNamedArgList : AstCompoundT<AstNodeId::NamedArgList>
{
};

struct AstUnnamedArgList : AstCompoundT<AstNodeId::UnnamedArgList>
{
};

struct AstLogicalExpr : AstBinaryT<AstNodeId::LogicalExpr>
{
};

struct AstRelationalExpr : AstBinaryT<AstNodeId::RelationalExpr>
{
};

struct AstBinaryExpr : AstBinaryT<AstNodeId::BinaryExpr>
{
    AstModifierFlags modifierFlags;
};

struct AstUnaryExpr : AstNodeT<AstNodeId::UnaryExpr>
{
    TokenRef   tokOp;
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstBinaryConditionalExpr : AstNodeT<AstNodeId::BinaryConditionalExpr>
{
    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeLeft, nodeRight});
    }
};

struct AstConditionalExpr : AstNodeT<AstNodeId::ConditionalExpr>
{
    AstNodeRef nodeCond;
    AstNodeRef nodeTrue;
    AstNodeRef nodeFalse;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeCond, nodeTrue, nodeFalse});
    }
};

struct AstInitializerExpr : AstNodeT<AstNodeId::InitializerExpr>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstIntegerLiteral : AstLiteralT<AstNodeId::IntegerLiteral>
{
};

struct AstFloatLiteral : AstLiteralT<AstNodeId::FloatLiteral>
{
};

struct AstStringLiteral : AstLiteralT<AstNodeId::StringLiteral>
{
};

struct AstCharacterLiteral : AstLiteralT<AstNodeId::CharacterLiteral>
{
};

struct AstBoolLiteral : AstLiteralT<AstNodeId::BoolLiteral>
{
};

struct AstNullLiteral : AstLiteralT<AstNodeId::NullLiteral>
{
};

struct AstCompilerLiteral : AstLiteralT<AstNodeId::CompilerLiteral>
{
};

struct AstSuffixLiteral : AstNodeT<AstNodeId::SuffixLiteral>
{
    AstNodeRef nodeLiteral;
    AstNodeRef nodeSuffix;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeLiteral, nodeSuffix});
    }
};

struct AstArrayLiteral : AstCompoundT<AstNodeId::ArrayLiteral>
{
};

struct AstStructLiteral : AstCompoundT<AstNodeId::StructLiteral>
{
};

struct AstScopeResolution : AstNodeT<AstNodeId::ScopeResolution>
{
    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeLeft, nodeRight});
    }
};

struct AstAsCastExpr : AstNodeT<AstNodeId::AsCastExpr>
{
    AstNodeRef nodeExpr;
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr, nodeType});
    }
};

struct AstIsTypeExpr : AstNodeT<AstNodeId::IsTypeExpr>
{
    AstNodeRef nodeExpr;
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr, nodeType});
    }
};

struct AstAutoCastExpr : AstNodeT<AstNodeId::AutoCastExpr>
{
    TokenRef         tokOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstExplicitCastExpr : AstNodeT<AstNodeId::ExplicitCastExpr>
{
    TokenRef         tokOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeType;
    AstNodeRef       nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType, nodeExpr});
    }
};

struct AstEnumBody : AstCompoundT<AstNodeId::EnumBody>
{
};

struct AstEnumDecl : AstNodeT<AstNodeId::EnumDecl>
{
    TokenRef   tokName;
    AstNodeRef nodeType;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType, nodeBody});
    }
};

struct AstEnumValue : AstNodeT<AstNodeId::EnumValue>
{
    TokenRef   tokName;
    AstNodeRef nodeValue;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeValue});
    }
};

struct AstEnumUse : AstNodeT<AstNodeId::EnumUse>
{
    AstNodeRef nodeName;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeName});
    }
};

struct AstImplEnum : AstCompoundT<AstNodeId::ImplEnum>
{
    AstNodeRef nodeName;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeName});
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstQualifiedType : AstNodeT<AstNodeId::QualifiedType>
{
    TokenRef   tokQual;
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType});
    }
};

struct AstLRefType : AstNodeT<AstNodeId::LRefType>
{
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType});
    }
};

struct AstRRefType : AstNodeT<AstNodeId::RRefType>
{
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType});
    }
};

struct AstPointerType : AstNodeT<AstNodeId::PointerType>
{
    AstNodeRef nodePointeeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodePointeeType});
    }
};

struct AstBlockPointerType : AstNodeT<AstNodeId::BlockPointerType>
{
    AstNodeRef nodePointeeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodePointeeType});
    }
};

struct AstSliceType : AstNodeT<AstNodeId::SliceType>
{
    AstNodeRef nodePointeeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodePointeeType});
    }
};

struct AstArrayType : AstNodeT<AstNodeId::ArrayType>
{
    SpanRef    spanDimensions;
    AstNodeRef nodePointeeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, ast, spanDimensions);
        AstNode::collectChildren(out, {nodePointeeType});
    }
};

struct AstNamedType : AstNodeT<AstNodeId::NamedType>
{
    AstNodeRef nodeIdent;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeIdent});
    }
};

struct AstBuiltinType : AstNodeT<AstNodeId::BuiltinType>
{
    TokenRef tokType;
};

struct AstCompilerTypeExpr : AstNodeT<AstNodeId::CompilerTypeExpr>
{
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType});
    }
};

struct AstLambdaType : AstNodeT<AstNodeId::LambdaType>
{
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

    SpanRef    spanParams;
    AstNodeRef nodeReturnType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, ast, spanParams);
        AstNode::collectChildren(out, {nodeReturnType});
    }
};

struct AstRetValType : AstNodeT<AstNodeId::RetValType>
{
};

struct AstCodeType : AstNodeT<AstNodeId::CodeType>
{
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType});
    }
};

struct AstVariadicType : AstNodeT<AstNodeId::VariadicType>
{
};

struct AstTypedVariadicType : AstNodeT<AstNodeId::TypedVariadicType>
{
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType});
    }
};

struct AstCompilerIf : AstNodeT<AstNodeId::CompilerIf>
{
    AstNodeRef nodeCondition;
    AstNodeRef nodeIfBlock;
    AstNodeRef nodeElseBlock;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeCondition, nodeIfBlock, nodeElseBlock});
    }
};

struct AstCompilerElse : AstCompoundT<AstNodeId::CompilerElse>
{
};

struct AstCompilerElseIf : AstCompoundT<AstNodeId::CompilerElseIf>
{
};

struct AstAttribute : AstNodeT<AstNodeId::Attribute>
{
    AstNodeRef nodeIdent;
    AstNodeRef nodeArgs;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeIdent, nodeArgs});
    }
};

struct AstAttributeList : AstCompoundT<AstNodeId::AttributeList>
{
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstCompoundT::collectChildren(out, ast);
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstDependencies : AstNodeT<AstNodeId::Dependencies>
{
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstUsingDecl : AstCompoundT<AstNodeId::UsingDecl>
{
};

struct AstStructDecl : AstAggregateDeclT<AstNodeId::StructDecl>
{
};

struct AstUnionDecl : AstAggregateDeclT<AstNodeId::UnionDecl>
{
};

struct AstAnonymousStructDecl : AstAnonymousAggregateDeclT<AstNodeId::AnonymousStructDecl>
{
};

struct AstAnonymousUnionDecl : AstAnonymousAggregateDeclT<AstNodeId::AnonymousUnionDecl>
{
};

struct AstAggregateBody : AstCompoundT<AstNodeId::AggregateBody>
{
};

struct AstAccessModifier : AstNodeT<AstNodeId::AccessModifier>
{
    TokenRef   tokAccess;
    AstNodeRef nodeWhat;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeWhat});
    }
};

struct AstConstraintBlock : AstCompoundT<AstNodeId::ConstraintBlock>
{
    TokenRef tokConstraint;
};

struct AstConstraintExpr : AstNodeT<AstNodeId::ConstraintExpr>
{
    TokenRef   tokConstraint;
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstGenericParamList : AstCompoundT<AstNodeId::GenericParamList>
{
};

template<AstNodeId I>
struct AstGenericParamT : AstNodeT<I>
{
    TokenRef   tokName;
    AstNodeRef nodeAssign;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeAssign});
    }
};

struct AstGenericValueParam : AstGenericParamT<AstNodeId::GenericValueParam>
{
    AstNodeRef nodeType;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeType});
        AstGenericParamT::collectChildren(out, ast);
    }
};

struct AstGenericTypeParam : AstGenericParamT<AstNodeId::GenericTypeParam>
{
};

struct AstVarDecl : AstNodeT<AstNodeId::VarDecl>
{
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

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType, nodeInit});
    }
};

struct AstVarMultiNameDecl : AstNodeT<AstNodeId::VarMultiNameDecl>
{
    SpanRef    spanNames;
    AstNodeRef nodeType;
    AstNodeRef nodeInit;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeType, nodeInit});
    }
};

struct AstVarDecompositionDecl : AstNodeT<AstNodeId::VarDecompositionDecl>
{
    SpanRef    spanNames;
    AstNodeRef nodeInit;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeInit});
    }
};

struct AstVarMultiDecl : AstCompoundT<AstNodeId::VarMultiDecl>
{
};

struct AstUndefined : AstNodeT<AstNodeId::Undefined>
{
};

struct AstUsingVarDecl : AstNodeT<AstNodeId::UsingVarDecl>
{
    AstNodeRef nodeVar;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeVar});
    }
};

struct AstAlias : AstNodeT<AstNodeId::Alias>
{
    TokenRef   tokName;
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstTryCatchExpr : AstNodeT<AstNodeId::TryCatchExpr>
{
    TokenRef   tokName;
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstUnreachableStmt : AstNodeT<AstNodeId::UnreachableStmt>
{
};

struct AstContinueStmt : AstNodeT<AstNodeId::ContinueStmt>
{
};

struct AstBreakStmt : AstNodeT<AstNodeId::BreakStmt>
{
};

struct AstScopedBreakStmt : AstNodeT<AstNodeId::ScopedBreakStmt>
{
    TokenRef tokName;
};

struct AstFallThroughStmt : AstNodeT<AstNodeId::FallThroughStmt>
{
};

struct AstDeferStmt : AstNodeT<AstNodeId::DeferStmt>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstIfStmt : AstIfBaseT<AstNodeId::IfStmt>
{
    AstNodeRef nodeCondition;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeCondition});
        AstIfBaseT::collectChildren(out, ast);
    }
};

struct AstIfVarDecl : AstIfBaseT<AstNodeId::IfVarDecl>
{
    AstNodeRef nodeVar;
    AstNodeRef nodeWhere;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeVar, nodeWhere});
        AstIfBaseT::collectChildren(out, ast);
    }
};

struct AstElseStmt : AstCompoundT<AstNodeId::ElseStmt>
{
};

struct AstElseIfStmt : AstCompoundT<AstNodeId::ElseIfStmt>
{
};

struct AstWithStmt : AstNodeT<AstNodeId::WithStmt>
{
    AstNodeRef nodeExpr;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr, nodeBody});
    }
};

struct AstWithVarDecl : AstNodeT<AstNodeId::WithVarDecl>
{
    AstNodeRef nodeVar;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeVar, nodeBody});
    }
};

struct AstIntrinsicInit : AstIntrinsicInitDropCopyMoveT<AstNodeId::IntrinsicInit>
{
    SpanRef spanArgs;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstIntrinsicInitDropCopyMoveT::collectChildren(out, ast);
        AstNode::collectChildren(out, ast, spanArgs);
    }
};

struct AstIntrinsicDrop : AstIntrinsicInitDropCopyMoveT<AstNodeId::IntrinsicDrop>
{
};

struct AstIntrinsicPostCopy : AstIntrinsicInitDropCopyMoveT<AstNodeId::IntrinsicPostCopy>
{
};

struct AstIntrinsicPostMove : AstIntrinsicInitDropCopyMoveT<AstNodeId::IntrinsicPostMove>
{
};

struct AstWhileStmt : AstNodeT<AstNodeId::WhileStmt>
{
    AstNodeRef nodeExpr;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr, nodeBody});
    }
};

struct AstForeachStmt : AstNodeT<AstNodeId::ForeachStmt>
{
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

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr, nodeWhere, nodeBody});
    }
};

struct AstForCppStmt : AstNodeT<AstNodeId::ForCppStmt>
{
    AstNodeRef nodeVarDecl;
    AstNodeRef nodeExpr;
    AstNodeRef nodePostStmt;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeVarDecl, nodeExpr, nodePostStmt, nodeBody});
    }
};

struct AstForLoopStmt : AstNodeT<AstNodeId::ForLoopStmt>
{
    AstModifierFlags modifierFlags;
    TokenRef         tokName;
    AstNodeRef       nodeExpr;
    AstNodeRef       nodeWhere;
    AstNodeRef       nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr, nodeWhere, nodeBody});
    }
};

struct AstForInfiniteStmt : AstNodeT<AstNodeId::ForInfiniteStmt>
{
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstTryCatchStmt : AstNodeT<AstNodeId::TryCatchStmt>
{
    TokenRef   tokOp;
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstThrowExpr : AstNodeT<AstNodeId::ThrowExpr>
{
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstDiscard : AstNodeT<AstNodeId::Discard>
{
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr});
    }
};

struct AstSwitchStmt : AstCompoundT<AstNodeId::SwitchStmt>
{
    AstNodeRef nodeExpr;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, {nodeExpr});
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstSwitchCaseStmt : AstCompoundT<AstNodeId::SwitchCaseStmt>
{
    SpanRef    spanExpr;
    AstNodeRef nodeWhere;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
    {
        AstNode::collectChildren(out, ast, spanExpr);
        AstNode::collectChildren(out, {nodeWhere});
        AstCompoundT::collectChildren(out, ast);
    }
};

struct AstCompilerMacro : AstNodeT<AstNodeId::CompilerMacro>
{
    AstNodeRef nodeBody;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

struct AstCompilerInject : AstNodeT<AstNodeId::CompilerInject>
{
    AstNodeRef nodeExpr;
    AstNodeRef nodeReplaceBreak;
    AstNodeRef nodeReplaceContinue;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExpr, nodeReplaceBreak, nodeReplaceContinue});
    }
};

struct AstRangeExpr : AstNodeT<AstNodeId::RangeExpr>
{
    enum class FlagsE : Flags
    {
        Zero      = 0,
        Inclusive = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;

    AstNodeRef nodeExprDown;
    AstNodeRef nodeExprUp;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeExprDown, nodeExprUp});
    }
};

struct AstAffectStmt : AstNodeT<AstNodeId::AffectStmt>
{
    TokenRef         tokOp;
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeLeft;
    AstNodeRef       nodeRight;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast*) const
    {
        AstNode::collectChildren(out, {nodeLeft, nodeRight});
    }
};

struct AstMultiAffect : AstCompoundT<AstNodeId::MultiAffect>
{
    enum FlagsE : Flags
    {
        Zero          = 0,
        Decomposition = 1 << 0,
    };
};
