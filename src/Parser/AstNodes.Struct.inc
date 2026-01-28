#pragma once

// -----------------------------------------------------------------------------
struct AstInvalid : AstNodeT<AstNodeId::Invalid>
{
};

// -----------------------------------------------------------------------------
struct AstFile : AstCompoundT<AstNodeId::File>
{
    SpanRef spanGlobalsRef;
    SpanRef spanUsingsRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanGlobalsRef);
        AstNode::collectChildren(out, ast, spanUsingsRef);
        AstCompoundT::collectChildren(out, ast);
    }

    Result        semaPreDecl(Sema& sema) const;
    static Result semaPreNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstTopLevelBlock : AstCompoundT<AstNodeId::TopLevelBlock>
{
};

// -----------------------------------------------------------------------------
struct AstEmbeddedBlock : AstCompoundT<AstNodeId::EmbeddedBlock>
{
};

// -----------------------------------------------------------------------------
enum class AstImplFlagsE : AstNode::ParserFlags
{
    Zero = 0,
    Enum = 1 << 0,
};

struct AstImpl : AstCompoundT<AstNodeId::Impl, AstImplFlagsE>
{
    AstNodeRef nodeIdentRef;
    AstNodeRef nodeForRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeIdentRef, nodeForRef});
        AstCompoundT::collectChildren(out, ast);
    }

    Result semaPostDeclChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
};

// -----------------------------------------------------------------------------
struct AstNamespaceDecl : AstCompoundT<AstNodeId::NamespaceDecl>
{
    SpanRef spanNameRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const { AstCompoundT::collectChildren(out, ast); }
    static Result pushNamespace(Sema& sema, const AstNode* node, SpanRef spanNameRef);
    static Result popNamespace(Sema& sema, SpanRef spanNameRef);
    Result        semaPreDecl(Sema& sema) const;
    Result        semaPostDecl(Sema& sema) const;
    Result        semaPreNode(Sema& sema) const;
    Result        semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstUsingNamespaceStmt : AstNodeT<AstNodeId::UsingNamespaceStmt>
{
    AstNodeRef nodeNameRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeNameRef}); }
};

// -----------------------------------------------------------------------------
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
        AccessPrivate,
        Namespace,
        CompilerIf,
        Using,
    };

    Mode       mode;
    SpanRef    spanNameRef;
    AstNodeRef nodeModeRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeModeRef}); }
    Result semaPreDecl(Sema& sema) const;
    Result semaPreNode(Sema& sema) const;
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerImport : AstNodeT<AstNodeId::CompilerImport>
{
    TokenRef tokModuleNameRef;
    TokenRef tokLocationRef;
    TokenRef tokVersionRef;
};

// -----------------------------------------------------------------------------
struct AstCompilerScope : AstNamedNodeT<AstNodeId::CompilerScope>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstCompilerExpression : AstNodeT<AstNodeId::CompilerExpression>
{
    AstNodeRef nodeExprRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstCompilerDiagnostic : AstInternalCallUnaryT<AstNodeId::CompilerDiagnostic>
{
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerCall : AstCompoundT<AstNodeId::CompilerCall>
{
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstIntrinsicCall : AstCompoundT<AstNodeId::IntrinsicCall>
{
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstIntrinsicCallVariadic : AstCompoundT<AstNodeId::IntrinsicCallVariadic>
{
};

// -----------------------------------------------------------------------------
struct AstIntrinsicValue : AstNodeT<AstNodeId::IntrinsicValue>
{
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
enum class AstFunctionFlagsE : AstNode::ParserFlags
{
    Zero      = 0,
    Method    = 1 << 0,
    Throwable = 1 << 1,
    Closure   = 1 << 2,
    Const     = 1 << 3,
    Impl      = 1 << 4,
    Short     = 1 << 5,
};

struct AstFunctionExpr : AstLambdaExprT<AstNodeId::FunctionExpr, AstFunctionFlagsE>
{
};

// -----------------------------------------------------------------------------
struct AstClosureExpr : AstLambdaExprT<AstNodeId::ClosureExpr, AstFunctionFlagsE>
{
    SpanRef nodeCaptureArgsRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, nodeCaptureArgsRef);
        AstLambdaExprT::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
struct AstFunctionDecl : AstNamedNodeT<AstNodeId::FunctionDecl, AstFunctionFlagsE>
{
    SpanRef    spanGenericParamsRef;
    AstNodeRef nodeParamsRef;
    AstNodeRef nodeReturnTypeRef;
    SpanRef    spanConstraintsRef;
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanGenericParamsRef);
        AstNode::collectChildren(out, {nodeParamsRef, nodeReturnTypeRef});
        AstNode::collectChildren(out, ast, spanConstraintsRef);
        AstNode::collectChildren(out, {nodeBodyRef});
    }

    Result        semaPreDecl(Sema& sema) const;
    Result        semaPreNode(Sema& sema) const;
    Result        semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result        semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    static Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstAttrDecl : AstNamedNodeT<AstNodeId::AttrDecl>
{
    AstNodeRef nodeParamsRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeParamsRef}); }
    Result        semaPreDecl(Sema& sema) const;
    Result        semaPreNode(Sema& sema) const;
    Result        semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    static Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
enum class AstFunctionParamMeFlagsE : AstNode::ParserFlags
{
    Zero  = 0,
    Const = 1 << 0,
};

struct AstFunctionParamMe : AstNodeT<AstNodeId::FunctionParamMe, AstFunctionParamMeFlagsE>
{
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstReturnStmt : AstNodeT<AstNodeId::ReturnStmt>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstFunctionBody : AstCompoundT<AstNodeId::FunctionBody>
{
};

// -----------------------------------------------------------------------------
enum class AstLambdaParamFlagsE : AstNode::ParserFlags
{
    Zero  = 0,
    Named = 1 << 0,
};

struct AstLambdaParam : AstNodeT<AstNodeId::LambdaParam, AstLambdaParamFlagsE>
{
    AstNodeRef nodeTypeRef;
    AstNodeRef nodeDefaultValueRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeDefaultValueRef}); }
};

// -----------------------------------------------------------------------------
struct AstFunctionParamList : AstCompoundT<AstNodeId::FunctionParamList>
{
};

// -----------------------------------------------------------------------------
enum class AstClosureArgumentFlagsE : AstNode::ParserFlags
{
    Zero    = 0,
    Address = 1 << 0,
};

struct AstClosureArgument : AstNodeT<AstNodeId::ClosureArgument, AstClosureArgumentFlagsE>
{
    AstNodeRef nodeIdentifierRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeIdentifierRef}); }
};

// -----------------------------------------------------------------------------
struct AstCompilerFunc : AstNodeT<AstNodeId::CompilerFunc>
{
    AstNodeRef nodeBodyRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
    Result        semaPreDecl(Sema& sema);
    static Result semaPreNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstCompilerMessageFunc : AstNodeT<AstNodeId::CompilerMessageFunc>
{
    AstNodeRef nodeParamRef;
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeParamRef, nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstCompilerRunBlock : AstNodeT<AstNodeId::CompilerRunBlock>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstCompilerRunExpr : AstNodeT<AstNodeId::CompilerRunExpr>
{
    AstNodeRef nodeExprRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    static Result semaPreNode(Sema&);
};

// -----------------------------------------------------------------------------
struct AstCompilerCodeBlock : AstNodeT<AstNodeId::CompilerCodeBlock>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstCompilerCodeExpr : AstNodeT<AstNodeId::CompilerCodeExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstCompilerShortFunc : AstNodeT<AstNodeId::CompilerShortFunc>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
enum class AstIdentifierFlagsE : AstNode::ParserFlags
{
    Zero              = 0,
    InCompilerDefined = 1 << 0,
    CallCallee        = 1 << 1,
};

struct AstIdentifier : AstNodeT<AstNodeId::Identifier, AstIdentifierFlagsE>
{
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstAncestorIdentifier : AstNodeT<AstNodeId::AncestorIdentifier>
{
    AstNodeRef nodeValueRef;
    AstNodeRef nodeIdentRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeValueRef, nodeIdentRef}); }
};

// -----------------------------------------------------------------------------
struct AstQuotedExpr : AstNodeT<AstNodeId::QuotedExpr>
{
    AstNodeRef nodeExprRef;
    AstNodeRef nodeSuffixRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeSuffixRef}); }
};

// -----------------------------------------------------------------------------
struct AstQuotedListExpr : AstCompoundT<AstNodeId::QuotedListExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeExprRef});
        AstCompoundT::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
struct AstCallExpr : AstCompoundT<AstNodeId::CallExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeExprRef});
        AstCompoundT::collectChildren(out, ast);
    }

    void collectArguments(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstCompoundT::collectChildren(out, ast);
    }

    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstAliasCallExpr : AstCompoundT<AstNodeId::AliasCallExpr>
{
    AstNodeRef nodeExprRef;
    SpanRef    spanAliasesRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeExprRef});
        AstNode::collectChildren(out, ast, spanAliasesRef);
        AstCompoundT::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
struct AstStructInitializerList : AstNodeT<AstNodeId::StructInitializerList>
{
    AstNodeRef nodeWhatRef;
    SpanRef    spanArgsRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeWhatRef});
        AstNode::collectChildren(out, ast, spanArgsRef);
    }
};

// -----------------------------------------------------------------------------
struct AstIndexExpr : AstNodeT<AstNodeId::IndexExpr>
{
    AstNodeRef nodeExprRef;
    AstNodeRef nodeArgRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeArgRef}); }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstIndexListExpr : AstCompoundT<AstNodeId::IndexListExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeExprRef});
        AstCompoundT::collectChildren(out, ast);
    }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstUnnamedArgument : AstNodeT<AstNodeId::UnnamedArgument>
{
};

// -----------------------------------------------------------------------------
struct AstNamedArgument : AstNodeT<AstNodeId::NamedArgument>
{
    AstNodeRef nodeArgRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeArgRef}); }
};

// -----------------------------------------------------------------------------
struct AstParenExpr : AstNodeT<AstNodeId::ParenExpr>
{
    AstNodeRef nodeExprRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstNamedArgumentList : AstCompoundT<AstNodeId::NamedArgumentList>
{
    static Result semaPreDecl(Sema&) { return Result::SkipChildren; }
    static Result semaPreNode(Sema&) { return Result::SkipChildren; }
};

// -----------------------------------------------------------------------------
struct AstUnnamedArgumentList : AstCompoundT<AstNodeId::UnnamedArgumentList>
{
};

// -----------------------------------------------------------------------------
struct AstLogicalExpr : AstBinaryT<AstNodeId::LogicalExpr>
{
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstRelationalExpr : AstBinaryT<AstNodeId::RelationalExpr>
{
    Result semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstBinaryExpr : AstBinaryT<AstNodeId::BinaryExpr>
{
    AstModifierFlags modifierFlags;

    Result semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstUnaryExpr : AstNodeT<AstNodeId::UnaryExpr>
{
    AstNodeRef nodeExprRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstBinaryConditionalExpr : AstNodeT<AstNodeId::BinaryConditionalExpr>
{
    AstNodeRef nodeLeftRef;
    AstNodeRef nodeRightRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeLeftRef, nodeRightRef}); }
    static Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstConditionalExpr : AstNodeT<AstNodeId::ConditionalExpr>
{
    AstNodeRef nodeCondRef;
    AstNodeRef nodeTrueRef;
    AstNodeRef nodeFalseRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeCondRef, nodeTrueRef, nodeFalseRef}); }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstInitializerExpr : AstNodeT<AstNodeId::InitializerExpr>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstBinaryLiteral : AstLiteralT<AstNodeId::BinaryLiteral>
{
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstHexaLiteral : AstLiteralT<AstNodeId::HexaLiteral>
{
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstIntegerLiteral : AstLiteralT<AstNodeId::IntegerLiteral>
{
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstFloatLiteral : AstLiteralT<AstNodeId::FloatLiteral>
{
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstStringLiteral : AstLiteralT<AstNodeId::StringLiteral>
{
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCharacterLiteral : AstLiteralT<AstNodeId::CharacterLiteral>
{
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstBoolLiteral : AstLiteralT<AstNodeId::BoolLiteral>
{
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstNullLiteral : AstLiteralT<AstNodeId::NullLiteral>
{
    static Result semaPreNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstCompilerLiteral : AstLiteralT<AstNodeId::CompilerLiteral>
{
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstSuffixLiteral : AstNodeT<AstNodeId::SuffixLiteral>
{
    AstNodeRef nodeLiteralRef;
    AstNodeRef nodeSuffixRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeLiteralRef, nodeSuffixRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstArrayLiteral : AstCompoundT<AstNodeId::ArrayLiteral>
{
};

// -----------------------------------------------------------------------------
struct AstStructLiteral : AstCompoundT<AstNodeId::StructLiteral>
{
};

// -----------------------------------------------------------------------------
enum class AstAutoMemberAccessExprFlagsE : AstNode::ParserFlags
{
    Zero         = 0,
    CallCallee   = 1 << 0,
    CallArgument = 1 << 1,
};

struct AstAutoMemberAccessExpr : AstNodeT<AstNodeId::AutoMemberAccessExpr, AstAutoMemberAccessExprFlagsE>
{
    AstNodeRef nodeIdentRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeIdentRef}); }
    Result semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
};

// -----------------------------------------------------------------------------
enum class AstMemberAccessExprFlagsE : AstNode::ParserFlags
{
    Zero       = 0,
    CallCallee = 1 << 0,
};

struct AstMemberAccessExpr : AstNodeT<AstNodeId::MemberAccessExpr, AstMemberAccessExprFlagsE>
{
    AstNodeRef nodeLeftRef;
    AstNodeRef nodeRightRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeLeftRef, nodeRightRef}); }
    Result semaPreNodeChild(Sema& sema, const AstNodeRef& childRef);
};

// -----------------------------------------------------------------------------
struct AstAsCastExpr : AstNodeT<AstNodeId::AsCastExpr>
{
    AstNodeRef nodeExprRef;
    AstNodeRef nodeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeTypeRef}); }
};

// -----------------------------------------------------------------------------
struct AstIsTypeExpr : AstNodeT<AstNodeId::IsTypeExpr>
{
    AstNodeRef nodeExprRef;
    AstNodeRef nodeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeTypeRef}); }
};

// -----------------------------------------------------------------------------
struct AstAutoCastExpr : AstNodeT<AstNodeId::AutoCastExpr>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExprRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstExplicitCastExpr : AstNodeT<AstNodeId::ExplicitCastExpr>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeTypeRef;
    AstNodeRef       nodeExprRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeExprRef}); }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstImplicitCastExpr : AstNodeT<AstNodeId::ImplicitCastExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstEnumBody : AstCompoundT<AstNodeId::EnumBody>
{
};

// -----------------------------------------------------------------------------
struct AstEnumDecl : AstNamedNodeT<AstNodeId::EnumDecl>
{
    AstNodeRef nodeTypeRef;
    AstNodeRef nodeBodyRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeBodyRef}); }
    Result semaPreDecl(Sema& sema) const;
    Result semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPreNode(Sema& sema) const;
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstEnumValue : AstNodeT<AstNodeId::EnumValue>
{
    AstNodeRef nodeInitRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeInitRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstUsingEnumDecl : AstNodeT<AstNodeId::UsingEnumDecl>
{
    AstNodeRef nodeNameRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeNameRef}); }
};

// -----------------------------------------------------------------------------
enum class AstQualifiedTypeFlagsE : AstNode::ParserFlags
{
    Zero     = 0,
    Const    = 1 << 0,
    Nullable = 1 << 1,
};

struct AstQualifiedType : AstNodeT<AstNodeId::QualifiedType, AstQualifiedTypeFlagsE>
{
    AstNodeRef nodeTypeRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstReferenceType : AstNodeT<AstNodeId::ReferenceType>
{
    AstNodeRef nodePointeeTypeRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodePointeeTypeRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstRRefType : AstNodeT<AstNodeId::RRefType>
{
    AstNodeRef nodePointeeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodePointeeTypeRef}); }
};

// -----------------------------------------------------------------------------
struct AstValuePointerType : AstNodeT<AstNodeId::ValuePointerType>
{
    AstNodeRef nodePointeeTypeRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodePointeeTypeRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstBlockPointerType : AstNodeT<AstNodeId::BlockPointerType>
{
    AstNodeRef nodePointeeTypeRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodePointeeTypeRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstSliceType : AstNodeT<AstNodeId::SliceType>
{
    AstNodeRef nodePointeeTypeRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodePointeeTypeRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstArrayType : AstNodeT<AstNodeId::ArrayType>
{
    SpanRef    spanDimensionsRef;
    AstNodeRef nodePointeeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanDimensionsRef);
        AstNode::collectChildren(out, {nodePointeeTypeRef});
    }

    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstNamedType : AstNodeT<AstNodeId::NamedType>
{
    AstNodeRef nodeIdentRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeIdentRef}); }
    Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstBuiltinType : AstNodeT<AstNodeId::BuiltinType>
{
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerTypeExpr : AstNodeT<AstNodeId::CompilerTypeExpr>
{
    AstNodeRef nodeTypeRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstLambdaType : AstNodeT<AstNodeId::LambdaType, AstFunctionFlagsE>
{
    SpanRef    spanParamsRef;
    AstNodeRef nodeReturnTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanParamsRef);
        AstNode::collectChildren(out, {nodeReturnTypeRef});
    }

    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstRetValType : AstNodeT<AstNodeId::RetValType>
{
};

// -----------------------------------------------------------------------------
struct AstCodeType : AstNodeT<AstNodeId::CodeType>
{
    AstNodeRef nodeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
};

// -----------------------------------------------------------------------------
struct AstVariadicType : AstNodeT<AstNodeId::VariadicType>
{
    static Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstTypedVariadicType : AstNodeT<AstNodeId::TypedVariadicType>
{
    AstNodeRef nodeTypeRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerIf : AstNodeT<AstNodeId::CompilerIf>
{
    AstNodeRef nodeConditionRef;
    AstNodeRef nodeIfBlockRef;
    AstNodeRef nodeElseBlockRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeConditionRef, nodeIfBlockRef, nodeElseBlockRef}); }
    Result semaPreDeclChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerElse : AstCompoundT<AstNodeId::CompilerElse>
{
};

// -----------------------------------------------------------------------------
struct AstAttribute : AstNodeT<AstNodeId::Attribute>
{
    AstNodeRef nodeIdentRef;
    AstNodeRef nodeArgsRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeIdentRef, nodeArgsRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstAttributeList : AstCompoundT<AstNodeId::AttributeList>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstCompoundT::collectChildren(out, ast);
        AstNode::collectChildren(out, {nodeBodyRef});
    }

    static Result semaPreNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstDependenciesBlock : AstCompoundT<AstNodeId::DependenciesBlock>
{
};

// -----------------------------------------------------------------------------
struct AstUsingDecl : AstCompoundT<AstNodeId::UsingDecl>
{
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstStructDecl : AstAggregateDeclT<AstNodeId::StructDecl>
{
    Result        semaPreDecl(Sema& sema) const;
    Result        semaPreNode(Sema& sema) const;
    Result        semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    static Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstUnionDecl : AstAggregateDeclT<AstNodeId::UnionDecl>
{
};

// -----------------------------------------------------------------------------
struct AstAnonymousStructDecl : AstAnonymousAggregateDeclT<AstNodeId::AnonymousStructDecl>
{
    Result        semaPreDecl(Sema& sema) const;
    Result        semaPreNode(Sema& sema) const;
    Result        semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    static Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstAnonymousUnionDecl : AstAnonymousAggregateDeclT<AstNodeId::AnonymousUnionDecl>
{
};

// -----------------------------------------------------------------------------
struct AstAggregateBody : AstCompoundT<AstNodeId::AggregateBody>
{
};

// -----------------------------------------------------------------------------
struct AstInterfaceDecl : AstAggregateDeclT<AstNodeId::InterfaceDecl>
{
    Result        semaPreDecl(Sema& sema) const;
    Result        semaPreNode(Sema& sema) const;
    Result        semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    static Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstInterfaceBody : AstCompoundT<AstNodeId::InterfaceBody>
{
};

// -----------------------------------------------------------------------------
struct AstAccessModifier : AstNodeT<AstNodeId::AccessModifier>
{
    AstNodeRef nodeWhatRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeWhatRef}); }
    Result        semaPreDecl(Sema& sema) const;
    Result        semaPreNode(Sema& sema) const;
    static Result semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstConstraintBlock : AstCompoundT<AstNodeId::ConstraintBlock>
{
};

// -----------------------------------------------------------------------------
struct AstConstraintExpr : AstNodeT<AstNodeId::ConstraintExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstGenericParamList : AstCompoundT<AstNodeId::GenericParamList>
{
};

// -----------------------------------------------------------------------------
struct AstGenericParamValue : AstGenericParamT<AstNodeId::GenericParamValue>
{
    AstNodeRef nodeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeTypeRef});
        AstGenericParamT::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
struct AstGenericParamType : AstGenericParamT<AstNodeId::GenericParamType>
{
};

// -----------------------------------------------------------------------------
enum class AstVarDeclFlagsE : AstNode::ParserFlags
{
    Zero      = 0,
    Var       = 1 << 0,
    Const     = 1 << 1,
    Let       = 1 << 2,
    Parameter = 1 << 3,
    Using     = 1 << 4,
};

struct AstVarDecl : AstNamedNodeT<AstNodeId::VarDecl, AstVarDeclFlagsE>
{
    AstNodeRef nodeTypeRef;
    AstNodeRef nodeInitRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeInitRef}); }
    Result semaPreDecl(Sema& sema) const;
    Result semaPreNode(Sema& sema) const;
    Result semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstVarDeclNameList : AstNodeT<AstNodeId::VarDeclNameList, AstVarDeclFlagsE>
{
    SpanRef    spanNamesRef;
    AstNodeRef nodeTypeRef;
    AstNodeRef nodeInitRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeInitRef}); }
    Result semaPreDecl(Sema& sema) const;
    Result semaPreNode(Sema& sema) const;
    Result semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstVarDeclDecomposition : AstNodeT<AstNodeId::VarDeclDecomposition, AstVarDeclFlagsE>
{
    SpanRef    spanNamesRef;
    AstNodeRef nodeInitRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeInitRef}); }
    Result semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstVarDeclList : AstCompoundT<AstNodeId::VarDeclList>
{
};

// -----------------------------------------------------------------------------
struct AstUndefinedExpr : AstNodeT<AstNodeId::UndefinedExpr>
{
    static Result semaPreNode(Sema& sema);
};

struct AstAliasDecl : AstNamedNodeT<AstNodeId::AliasDecl>
{
    AstNodeRef nodeExprRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    Result semaPostNode(Sema& sema) const;
    Result semaPreDecl(Sema& sema) const;
    Result semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstTryCatchExpr : AstNodeT<AstNodeId::TryCatchExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstUnreachableStmt : AstNodeT<AstNodeId::UnreachableStmt>
{
};

// -----------------------------------------------------------------------------
struct AstContinueStmt : AstNodeT<AstNodeId::ContinueStmt>
{
    static Result semaPreNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstBreakStmt : AstNodeT<AstNodeId::BreakStmt>
{
    static Result semaPreNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstScopedBreakStmt : AstNamedNodeT<AstNodeId::ScopedBreakStmt>
{
};

// -----------------------------------------------------------------------------
struct AstFallThroughStmt : AstNodeT<AstNodeId::FallThroughStmt>
{
};

// -----------------------------------------------------------------------------
struct AstDeferStmt : AstNodeT<AstNodeId::DeferStmt>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstIfStmt : AstIfBaseT<AstNodeId::IfStmt>
{
    AstNodeRef nodeConditionRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeConditionRef});
        AstIfBaseT::collectChildren(out, ast);
    }

    Result semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
};

// -----------------------------------------------------------------------------
struct AstIfVarDecl : AstIfBaseT<AstNodeId::IfVarDecl>
{
    AstNodeRef nodeVarRef;
    AstNodeRef nodeWhereRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeVarRef, nodeWhereRef});
        AstIfBaseT::collectChildren(out, ast);
    }

    static Result semaPreNode(Sema&) { return Result::SkipChildren; }
};

// -----------------------------------------------------------------------------
struct AstElseStmt : AstCompoundT<AstNodeId::ElseStmt>
{
    static Result semaPreNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstElseIfStmt : AstCompoundT<AstNodeId::ElseIfStmt>
{
    static Result semaPreNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstWithStmt : AstNodeT<AstNodeId::WithStmt>
{
    AstNodeRef nodeExprRef;
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstWithVarDecl : AstNodeT<AstNodeId::WithVarDecl>
{
    AstNodeRef nodeVarRef;
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeVarRef, nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstIntrinsicInit : AstIntrinsicInitDropCopyMoveT<AstNodeId::IntrinsicInit>
{
    SpanRef spanArgsRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstIntrinsicInitDropCopyMoveT::collectChildren(out, ast);
        AstNode::collectChildren(out, ast, spanArgsRef);
    }
};

// -----------------------------------------------------------------------------
struct AstIntrinsicDrop : AstIntrinsicInitDropCopyMoveT<AstNodeId::IntrinsicDrop>
{
};

// -----------------------------------------------------------------------------
struct AstIntrinsicPostCopy : AstIntrinsicInitDropCopyMoveT<AstNodeId::IntrinsicPostCopy>
{
};

// -----------------------------------------------------------------------------
struct AstIntrinsicPostMove : AstIntrinsicInitDropCopyMoveT<AstNodeId::IntrinsicPostMove>
{
};

// -----------------------------------------------------------------------------
struct AstWhileStmt : AstNodeT<AstNodeId::WhileStmt>
{
    AstNodeRef nodeExprRef;
    AstNodeRef nodeBodyRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeBodyRef}); }
    Result semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    Result semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
};

// -----------------------------------------------------------------------------
enum class AstForeachStmtFlagsE : AstNode::ParserFlags
{
    Zero      = 0,
    ByAddress = 1 << 0,
};

struct AstForeachStmt : AstNodeT<AstNodeId::ForeachStmt, AstForeachStmtFlagsE>
{
    TokenRef         tokSpecializationRef;
    AstModifierFlags modifierFlags;
    SpanRef          spanNamesRef;
    AstNodeRef       nodeExprRef;
    AstNodeRef       nodeWhereRef;
    AstNodeRef       nodeBodyRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeWhereRef, nodeBodyRef}); }
    static Result semaPreNode(Sema&) { return Result::SkipChildren; }
};

// -----------------------------------------------------------------------------
struct AstForCStyleStmt : AstNodeT<AstNodeId::ForCStyleStmt>
{
    AstNodeRef nodeVarDeclRef;
    AstNodeRef nodeExprRef;
    AstNodeRef nodePostStmtRef;
    AstNodeRef nodeBodyRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeVarDeclRef, nodeExprRef, nodePostStmtRef, nodeBodyRef}); }
    static Result semaPreNode(Sema&) { return Result::SkipChildren; }
};

// -----------------------------------------------------------------------------
struct AstForStmt : AstNamedNodeT<AstNodeId::ForStmt>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExprRef;
    AstNodeRef       nodeWhereRef;
    AstNodeRef       nodeBodyRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeWhereRef, nodeBodyRef}); }
    static Result semaPreNode(Sema&) { return Result::SkipChildren; }
};

// -----------------------------------------------------------------------------
struct AstInfiniteLoopStmt : AstNodeT<AstNodeId::InfiniteLoopStmt>
{
    AstNodeRef nodeBodyRef;

    void   collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
    Result semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
};

// -----------------------------------------------------------------------------
struct AstTryCatchStmt : AstNodeT<AstNodeId::TryCatchStmt>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstThrowExpr : AstNodeT<AstNodeId::ThrowExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstDiscardExpr : AstNodeT<AstNodeId::DiscardExpr>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstSwitchStmt : AstCompoundT<AstNodeId::SwitchStmt>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeExprRef});
        AstCompoundT::collectChildren(out, ast);
    }

    static Result semaPreNodeChild(Sema& sema, const AstNodeRef& childRef);
    Result        semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
};

// -----------------------------------------------------------------------------
struct AstSwitchCaseStmt : AstCompoundT<AstNodeId::SwitchCaseStmt>
{
    SpanRef    spanExprRef;
    AstNodeRef nodeWhereRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanExprRef);
        AstNode::collectChildren(out, {nodeWhereRef});
        AstCompoundT::collectChildren(out, ast);
    }

    static Result semaPreNode(Sema& sema);
    Result        semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerMacro : AstNodeT<AstNodeId::CompilerMacro>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstCompilerInject : AstNodeT<AstNodeId::CompilerInject>
{
    AstNodeRef nodeExprRef;
    AstNodeRef nodeReplaceBreakRef;
    AstNodeRef nodeReplaceContinueRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeReplaceBreakRef, nodeReplaceContinueRef}); }
};

// -----------------------------------------------------------------------------
enum class AstRangeExprFlagsE : AstNode::ParserFlags
{
    Zero      = 0,
    Inclusive = 1 << 0,
};

struct AstRangeExpr : AstNodeT<AstNodeId::RangeExpr, AstRangeExprFlagsE>
{
    AstNodeRef nodeExprDownRef;
    AstNodeRef nodeExprUpRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprDownRef, nodeExprUpRef}); }
};

// -----------------------------------------------------------------------------
struct AstAssignStmt : AstNodeT<AstNodeId::AssignStmt>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeLeftRef;
    AstNodeRef       nodeRightRef;

    void          collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeLeftRef, nodeRightRef}); }
    static Result semaPreNode(Sema&) { return Result::SkipChildren; }
};

// -----------------------------------------------------------------------------
enum class AstAssignListStmtFlagsE : AstNode::ParserFlags
{
    Zero          = 0,
    Decomposition = 1 << 0,
};

struct AstAssignListStmt : AstCompoundT<AstNodeId::AssignListStmt, AstAssignListStmtFlagsE>
{
};
