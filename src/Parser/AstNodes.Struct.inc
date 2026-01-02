#pragma once

// -----------------------------------------------------------------------------
struct AstInvalid : AstNodeT<AstNodeId::Invalid>
{
};

// -----------------------------------------------------------------------------
struct AstFile : AstCompoundT<AstNodeId::File>
{
    SpanRef spanGlobalsRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanGlobalsRef);
        AstCompoundT::collectChildren(out, ast);
    }

    AstVisitStepResult        semaPreDecl(Sema& sema) const;
    static AstVisitStepResult semaPostDecl(Sema& sema);
    static AstVisitStepResult semaPreNode(Sema& sema);
    static AstVisitStepResult semaPostNode(Sema& sema);
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
struct AstImpl : AstCompoundT<AstNodeId::Impl>
{
    AstNodeRef nodeIdentRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeIdentRef});
        AstCompoundT::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
struct AstImplFor : AstCompoundT<AstNodeId::ImplFor>
{
    AstNodeRef nodeIdentRef;
    AstNodeRef nodeForRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeIdentRef, nodeForRef});
        AstCompoundT::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
struct AstNamespaceDecl : AstCompoundT<AstNodeId::NamespaceDecl>
{
    SpanRef spanNameRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const { AstCompoundT::collectChildren(out, ast); }
    AstVisitStepResult semaPreDecl(Sema& sema) const;
    AstVisitStepResult semaPostDecl(Sema& sema) const;
    AstVisitStepResult semaPreNode(Sema& sema) const;
    AstVisitStepResult semaPostNode(Sema& sema) const;
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

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const { AstNode::collectChildren(out, {nodeModeRef}); }
    AstVisitStepResult semaPreDecl(Sema& sema) const;
    AstVisitStepResult semaPostDecl(Sema& sema) const;
    AstVisitStepResult semaPreNode(Sema& sema) const;
    AstVisitStepResult semaPostNode(Sema& sema) const;
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

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstCompilerDiagnostic : AstInternalCallUnaryT<AstNodeId::CompilerDiagnostic>
{
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerCallUnary : AstInternalCallUnaryT<AstNodeId::CompilerCallUnary>
{
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstIntrinsicCallZero : AstInternalCallZeroT<AstNodeId::IntrinsicCallZero>
{
};

// -----------------------------------------------------------------------------
struct AstIntrinsicCallUnary : AstInternalCallUnaryT<AstNodeId::IntrinsicCallUnary>
{
};

// -----------------------------------------------------------------------------
struct AstIntrinsicCallBinary : AstInternalCallBinaryT<AstNodeId::IntrinsicCallBinary>
{
};

// -----------------------------------------------------------------------------
struct AstIntrinsicCallTernary : AstInternalCallTernaryT<AstNodeId::IntrinsicCallTernary>
{
};

// -----------------------------------------------------------------------------
struct AstIntrinsicCallVariadic : AstCompoundT<AstNodeId::IntrinsicCallVariadic>
{
};

// -----------------------------------------------------------------------------
struct AstIntrinsicValue : AstNodeT<AstNodeId::IntrinsicValue>
{
    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstFunctionExpr : AstLambdaExprT<AstNodeId::FunctionExpr>
{
};

// -----------------------------------------------------------------------------
struct AstClosureExpr : AstLambdaExprT<AstNodeId::ClosureExpr>
{
    SpanRef nodeCaptureArgsRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, nodeCaptureArgsRef);
        AstLambdaExprT::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
struct AstFunctionDecl : AstNamedNodeT<AstNodeId::FunctionDecl>
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

    static AstVisitStepResult semaPreDecl(Sema&) { return AstVisitStepResult::SkipChildren; }
    static AstVisitStepResult semaPreNode(Sema&) { return AstVisitStepResult::SkipChildren; }
};

// -----------------------------------------------------------------------------
struct AstAttrDecl : AstNamedNodeT<AstNodeId::AttrDecl>
{
    AstNodeRef nodeParamsRef;

    void                      collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeParamsRef}); }
    AstVisitStepResult        semaPreDecl(Sema& sema) const;
    static void               semaEnterNode(Sema& sema);
    static AstVisitStepResult semaPreNode(Sema& sema);
    static AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstFunctionParamMe : AstNodeT<AstNodeId::FunctionParamMe>
{
    enum FlagsE : ParserFlags
    {
        Zero  = 0,
        Const = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;
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
struct AstLambdaTypeParam : AstNodeT<AstNodeId::LambdaTypeParam>
{
    AstNodeRef nodeTypeRef;
    AstNodeRef nodeDefaultValueRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeDefaultValueRef}); }
};

// -----------------------------------------------------------------------------
struct AstFunctionParamList : AstCompoundT<AstNodeId::FunctionParamList>
{
    static AstVisitStepResult semaPreNode(Sema&) { return AstVisitStepResult::SkipChildren; }
};

// -----------------------------------------------------------------------------
struct AstClosureArgument : AstNodeT<AstNodeId::ClosureArgument>
{
    enum FlagsE : ParserFlags
    {
        Zero    = 0,
        Address = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;

    AstNodeRef nodeIdentifierRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeIdentifierRef}); }
};

// -----------------------------------------------------------------------------
struct AstCompilerFunc : AstNodeT<AstNodeId::CompilerFunc>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
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

    void                      collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    static AstVisitStepResult semaPreNode(Sema&);
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
struct AstIdentifier : AstNodeT<AstNodeId::Identifier>
{
    enum FlagsE : ParserFlags
    {
        Zero              = 0,
        InCompilerDefined = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;

    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstAutoScopedIdentifier : AstNodeT<AstNodeId::AutoScopedIdentifier>
{
    AstNodeRef nodeIdentRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeIdentRef}); }
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

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeArgRef}); }
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

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstNamedArgumentList : AstCompoundT<AstNodeId::NamedArgumentList>
{
};

// -----------------------------------------------------------------------------
struct AstUnnamedArgumentList : AstCompoundT<AstNodeId::UnnamedArgumentList>
{
};

// -----------------------------------------------------------------------------
struct AstLogicalExpr : AstBinaryT<AstNodeId::LogicalExpr>
{
    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstRelationalExpr : AstBinaryT<AstNodeId::RelationalExpr>
{
    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstBinaryExpr : AstBinaryT<AstNodeId::BinaryExpr>
{
    AstModifierFlags modifierFlags;

    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstUnaryExpr : AstNodeT<AstNodeId::UnaryExpr>
{
    AstNodeRef nodeExprRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstBinaryConditionalExpr : AstNodeT<AstNodeId::BinaryConditionalExpr>
{
    AstNodeRef nodeLeftRef;
    AstNodeRef nodeRightRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeLeftRef, nodeRightRef}); }
};

// -----------------------------------------------------------------------------
struct AstConditionalExpr : AstNodeT<AstNodeId::ConditionalExpr>
{
    AstNodeRef nodeCondRef;
    AstNodeRef nodeTrueRef;
    AstNodeRef nodeFalseRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeCondRef, nodeTrueRef, nodeFalseRef}); }
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
    AstVisitStepResult semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstHexaLiteral : AstLiteralT<AstNodeId::HexaLiteral>
{
    AstVisitStepResult semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstIntegerLiteral : AstLiteralT<AstNodeId::IntegerLiteral>
{
    AstVisitStepResult semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstFloatLiteral : AstLiteralT<AstNodeId::FloatLiteral>
{
    AstVisitStepResult semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstStringLiteral : AstLiteralT<AstNodeId::StringLiteral>
{
    AstVisitStepResult semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCharacterLiteral : AstLiteralT<AstNodeId::CharacterLiteral>
{
    AstVisitStepResult semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstBoolLiteral : AstLiteralT<AstNodeId::BoolLiteral>
{
    AstVisitStepResult semaPreNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstNullLiteral : AstLiteralT<AstNodeId::NullLiteral>
{
};

// -----------------------------------------------------------------------------
struct AstCompilerLiteral : AstLiteralT<AstNodeId::CompilerLiteral>
{
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstSuffixLiteral : AstNodeT<AstNodeId::SuffixLiteral>
{
    AstNodeRef nodeLiteralRef;
    AstNodeRef nodeSuffixRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeLiteralRef, nodeSuffixRef}); }
    AstVisitStepResult semaPostNode(Sema& sema) const;
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
struct AstMemberAccessExpr : AstNodeT<AstNodeId::MemberAccessExpr>
{
    AstNodeRef nodeLeftRef;
    AstNodeRef nodeRightRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeLeftRef, nodeRightRef}); }
    AstVisitStepResult semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
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

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
};

// -----------------------------------------------------------------------------
struct AstExplicitCastExpr : AstNodeT<AstNodeId::ExplicitCastExpr>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeTypeRef;
    AstNodeRef       nodeExprRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeExprRef}); }
    AstVisitStepResult semaPostNode(Sema& sema);
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

    void                      collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeBodyRef}); }
    AstVisitStepResult        semaPreDecl(Sema& sema) const;
    AstVisitStepResult        semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    static void               semaEnterNode(Sema& sema);
    static AstVisitStepResult semaPreNode(Sema& sema);
    AstVisitStepResult        semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstEnumValue : AstNodeT<AstNodeId::EnumValue>
{
    AstNodeRef nodeInitRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeInitRef}); }
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstUsingEnumDecl : AstNodeT<AstNodeId::UsingEnumDecl>
{
    AstNodeRef nodeNameRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeNameRef}); }
};

// -----------------------------------------------------------------------------
struct AstImplEnum : AstCompoundT<AstNodeId::ImplEnum>
{
    AstNodeRef nodeNameRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeNameRef});
        AstCompoundT::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
struct AstQualifiedType : AstNodeT<AstNodeId::QualifiedType>
{
    enum FlagsE : ParserFlags
    {
        Zero     = 0,
        Const    = 1 << 0,
        Nullable = 1 << 1,
    };
    using Flags = EnumFlags<FlagsE>;

    AstNodeRef nodeTypeRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstLRefType : AstNodeT<AstNodeId::LRefType>
{
    AstNodeRef nodeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
};

// -----------------------------------------------------------------------------
struct AstRRefType : AstNodeT<AstNodeId::RRefType>
{
    AstNodeRef nodeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
};

// -----------------------------------------------------------------------------
struct AstValuePointerType : AstNodeT<AstNodeId::ValuePointerType>
{
    AstNodeRef nodePointeeTypeRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodePointeeTypeRef}); }
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstBlockPointerType : AstNodeT<AstNodeId::BlockPointerType>
{
    AstNodeRef nodePointeeTypeRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodePointeeTypeRef}); }
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstSliceType : AstNodeT<AstNodeId::SliceType>
{
    AstNodeRef nodePointeeTypeRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodePointeeTypeRef}); }
    AstVisitStepResult semaPostNode(Sema& sema) const;
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

    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstNamedType : AstNodeT<AstNodeId::NamedType>
{
    AstNodeRef nodeIdentRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeIdentRef}); }
    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstBuiltinType : AstNodeT<AstNodeId::BuiltinType>
{
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerTypeExpr : AstNodeT<AstNodeId::CompilerTypeExpr>
{
    AstNodeRef nodeTypeRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
    AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstLambdaType : AstNodeT<AstNodeId::LambdaType>
{
    enum FlagsE : ParserFlags
    {
        Zero    = 0,
        Mtd     = 1 << 0,
        Throw   = 1 << 1,
        Closure = 1 << 2,
        Const   = 1 << 3,
        Impl    = 1 << 4,
    };
    using Flags = EnumFlags<FlagsE>;

    SpanRef    spanParamsRef;
    AstNodeRef nodeReturnTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanParamsRef);
        AstNode::collectChildren(out, {nodeReturnTypeRef});
    }
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
};

// -----------------------------------------------------------------------------
struct AstTypedVariadicType : AstNodeT<AstNodeId::TypedVariadicType>
{
    AstNodeRef nodeTypeRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
};

// -----------------------------------------------------------------------------
struct AstValueType : AstNodeT<AstNodeId::ValueType>
{
    AstNodeRef nodeTypeRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef}); }
    AstVisitStepResult semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstCompilerIf : AstNodeT<AstNodeId::CompilerIf>
{
    AstNodeRef nodeConditionRef;
    AstNodeRef nodeIfBlockRef;
    AstNodeRef nodeElseBlockRef;

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeConditionRef, nodeIfBlockRef, nodeElseBlockRef}); }
    AstVisitStepResult semaPreDeclChild(Sema& sema, const AstNodeRef& childRef) const;
    AstVisitStepResult semaPostDecl(Sema& sema) const;
    AstVisitStepResult semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    AstVisitStepResult semaPostNode(Sema& sema) const;
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

    void               collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeIdentRef, nodeArgsRef}); }
    AstVisitStepResult semaPostNode(Sema& sema) const;
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

    static AstVisitStepResult semaPreNode(Sema& sema);
    static AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstDependenciesBlock : AstCompoundT<AstNodeId::DependenciesBlock>
{
};

// -----------------------------------------------------------------------------
struct AstUsingDecl : AstCompoundT<AstNodeId::UsingDecl>
{
};

// -----------------------------------------------------------------------------
struct AstStructDecl : AstAggregateDeclT<AstNodeId::StructDecl>
{
    AstVisitStepResult        semaPreDecl(Sema& sema) const;
    static void               semaEnterNode(Sema& sema);
    static AstVisitStepResult semaPreNode(Sema& sema);
    AstVisitStepResult        semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    static AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstUnionDecl : AstAggregateDeclT<AstNodeId::UnionDecl>
{
};

// -----------------------------------------------------------------------------
struct AstAnonymousStructDecl : AstAnonymousAggregateDeclT<AstNodeId::AnonymousStructDecl>
{
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
struct AstInterfaceDecl : AstNamedNodeT<AstNodeId::InterfaceDecl>
{
    AstNodeRef nodeBodyRef;

    void                      collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
    AstVisitStepResult        semaPreDecl(Sema& sema) const;
    static void               semaEnterNode(Sema& sema);
    static AstVisitStepResult semaPreNode(Sema& sema);
    AstVisitStepResult        semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const;
    static AstVisitStepResult semaPostNode(Sema& sema);
};

// -----------------------------------------------------------------------------
struct AstInterfaceBody : AstCompoundT<AstNodeId::InterfaceBody>
{
};

// -----------------------------------------------------------------------------
struct AstAccessModifier : AstNodeT<AstNodeId::AccessModifier>
{
    AstNodeRef nodeWhatRef;

    void                      collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeWhatRef}); }
    AstVisitStepResult        semaPreDecl(Sema& sema) const;
    static AstVisitStepResult semaPostDecl(Sema& sema);
    AstVisitStepResult        semaPreNode(Sema& sema) const;
    static AstVisitStepResult semaPostNode(Sema& sema);
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
struct AstVarDecl : AstNamedNodeT<AstNodeId::VarDecl>
{
    enum FlagsE : ParserFlags
    {
        Zero  = 0,
        Var   = 1 << 0,
        Const = 1 << 1,
        Let   = 1 << 2,
    };
    using Flags = EnumFlags<FlagsE>;

    AstNodeRef nodeTypeRef;
    AstNodeRef nodeInitRef;

    void                      collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeInitRef}); }
    AstVisitStepResult        semaPreDecl(Sema& sema) const;
    void                      semaEnterNode(Sema& sema) const;
    static AstVisitStepResult semaPreNode(Sema& sema);
    AstVisitStepResult        semaPostNode(Sema& sema) const;
};

// -----------------------------------------------------------------------------
struct AstVarDeclNameList : AstNodeT<AstNodeId::VarDeclNameList>
{
    SpanRef    spanNamesRef;
    AstNodeRef nodeTypeRef;
    AstNodeRef nodeInitRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeTypeRef, nodeInitRef}); }
};

// -----------------------------------------------------------------------------
struct AstVarDeclDecomposition : AstNodeT<AstNodeId::VarDeclDecomposition>
{
    SpanRef    spanNamesRef;
    AstNodeRef nodeInitRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeInitRef}); }
};

// -----------------------------------------------------------------------------
struct AstVarDeclList : AstCompoundT<AstNodeId::VarDeclList>
{
};

// -----------------------------------------------------------------------------
struct AstUndefinedExpr : AstNodeT<AstNodeId::UndefinedExpr>
{
};

// -----------------------------------------------------------------------------
struct AstUsingMemberDecl : AstNodeT<AstNodeId::UsingMemberDecl>
{
    AstNodeRef nodeVarRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeVarRef}); }
};

// -----------------------------------------------------------------------------
struct AstAliasDecl : AstNamedNodeT<AstNodeId::AliasDecl>
{
    AstNodeRef nodeExprRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef}); }
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
};

// -----------------------------------------------------------------------------
struct AstBreakStmt : AstNodeT<AstNodeId::BreakStmt>
{
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
};

// -----------------------------------------------------------------------------
struct AstElseStmt : AstCompoundT<AstNodeId::ElseStmt>
{
};

// -----------------------------------------------------------------------------
struct AstElseIfStmt : AstCompoundT<AstNodeId::ElseIfStmt>
{
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

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstForeachStmt : AstNodeT<AstNodeId::ForeachStmt>
{
    enum FlagsE : ParserFlags
    {
        Zero      = 0,
        ByAddress = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;

    TokenRef         tokSpecializationRef;
    AstModifierFlags modifierFlags;
    SpanRef          spanNamesRef;
    AstNodeRef       nodeExprRef;
    AstNodeRef       nodeWhereRef;
    AstNodeRef       nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeWhereRef, nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstForCStyleStmt : AstNodeT<AstNodeId::ForCStyleStmt>
{
    AstNodeRef nodeVarDeclRef;
    AstNodeRef nodeExprRef;
    AstNodeRef nodePostStmtRef;
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeVarDeclRef, nodeExprRef, nodePostStmtRef, nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstForStmt : AstNamedNodeT<AstNodeId::ForStmt>
{
    AstModifierFlags modifierFlags;
    AstNodeRef       nodeExprRef;
    AstNodeRef       nodeWhereRef;
    AstNodeRef       nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeExprRef, nodeWhereRef, nodeBodyRef}); }
};

// -----------------------------------------------------------------------------
struct AstInfiniteLoopStmt : AstNodeT<AstNodeId::InfiniteLoopStmt>
{
    AstNodeRef nodeBodyRef;

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeBodyRef}); }
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
struct AstRangeExpr : AstNodeT<AstNodeId::RangeExpr>
{
    enum FlagsE : ParserFlags
    {
        Zero      = 0,
        Inclusive = 1 << 0,
    };
    using Flags = EnumFlags<FlagsE>;

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

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const { AstNode::collectChildren(out, {nodeLeftRef, nodeRightRef}); }
};

// -----------------------------------------------------------------------------
struct AstAssignListStmt : AstCompoundT<AstNodeId::AssignListStmt>
{
    enum FlagsE : ParserFlags
    {
        Zero          = 0,
        Decomposition = 1 << 0,
    };
};
