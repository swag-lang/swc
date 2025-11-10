SWC_NODE_DEF(Invalid)

// Structural
SWC_NODE_DEF(TopLevelBlock)
SWC_NODE_DEF(EmbeddedBlock)
SWC_NODE_DEF(File)
SWC_NODE_DEF(Namespace)
SWC_NODE_DEF(UsingNamespace)
SWC_NODE_DEF(Dependencies)
SWC_NODE_DEF(UsingDecl)
SWC_NODE_DEF(UsingVarDecl)
SWC_NODE_DEF(AccessModifier)
SWC_NODE_DEF(ConstraintBlock)
SWC_NODE_DEF(ConstraintExpr)
SWC_NODE_DEF(Alias)
SWC_NODE_DEF(TryCatchAssumeExpr)

// Identifiers & References
SWC_NODE_DEF(Identifier)
SWC_NODE_DEF(PreQualifiedIdentifier)
SWC_NODE_DEF(AncestorIdentifier)
SWC_NODE_DEF(PostfixIdentifier)
SWC_NODE_DEF(MultiPostfixIdentifier)
SWC_NODE_DEF(ScopeResolution)

// Postfix
SWC_NODE_DEF(IndexExpr)
SWC_NODE_DEF(MultiIndexExpr)
SWC_NODE_DEF(SlicingExpr)
SWC_NODE_DEF(StructInitializerList)

// Expressions — Unary & Binary
SWC_NODE_DEF(ParenExpr)
SWC_NODE_DEF(LogicalExpr)
SWC_NODE_DEF(RelationalExpr)
SWC_NODE_DEF(BinaryExpr)
SWC_NODE_DEF(UnaryExpr)
SWC_NODE_DEF(InitializerExpr)
SWC_NODE_DEF(BinaryConditionalOp)
SWC_NODE_DEF(ConditionalOp)
SWC_NODE_DEF(DeRefOp)

// Type Casting & Checks
SWC_NODE_DEF(ExplicitCastExpr)
SWC_NODE_DEF(AutoCastExpr)
SWC_NODE_DEF(AsCastExpr)
SWC_NODE_DEF(IsTypeExpr)

// Literals
SWC_NODE_DEF(ArrayLiteral)
SWC_NODE_DEF(StructLiteral)
SWC_NODE_DEF(BoolLiteral)
SWC_NODE_DEF(CharacterLiteral)
SWC_NODE_DEF(CompilerLiteral)
SWC_NODE_DEF(FloatLiteral)
SWC_NODE_DEF(IntegerLiteral)
SWC_NODE_DEF(NullLiteral)
SWC_NODE_DEF(PostfixedLiteral)
SWC_NODE_DEF(StringLiteral)

// Compiler Builtins
SWC_NODE_DEF(CompilerAssert)
SWC_NODE_DEF(CompilerError)
SWC_NODE_DEF(CompilerWarning)
SWC_NODE_DEF(CompilerFunc)
SWC_NODE_DEF(CompilerShortFunc)
SWC_NODE_DEF(CompilerEmbeddedFunc)
SWC_NODE_DEF(CompilerExpr)
SWC_NODE_DEF(CompilerPrint)
SWC_NODE_DEF(CompilerCallUnary)
SWC_NODE_DEF(CompilerTypeExpr)
SWC_NODE_DEF(CompilerGlobal)
SWC_NODE_DEF(CompilerImport)

// Intrinsics
SWC_NODE_DEF(IntrinsicCallZero)
SWC_NODE_DEF(IntrinsicCallUnary)
SWC_NODE_DEF(IntrinsicCallBinary)
SWC_NODE_DEF(IntrinsicCallTernary)
SWC_NODE_DEF(IntrinsicValue)

// Types
SWC_NODE_DEF(ArrayType)
SWC_NODE_DEF(BlockPointerType)
SWC_NODE_DEF(BuiltinType)
SWC_NODE_DEF(IncompleteArrayType)
SWC_NODE_DEF(LRefType)
SWC_NODE_DEF(RRefType)
SWC_NODE_DEF(NamedType)
SWC_NODE_DEF(PointerType)
SWC_NODE_DEF(QualifiedType)
SWC_NODE_DEF(SliceType)
SWC_NODE_DEF(LambdaType)
SWC_NODE_DEF(RetValType)
SWC_NODE_DEF(CodeType)
SWC_NODE_DEF(VariadicType)
SWC_NODE_DEF(TypedVariadicType)

// Structs
SWC_NODE_DEF(AggregateBody)
SWC_NODE_DEF(StructDecl)
SWC_NODE_DEF(UnionDecl)
SWC_NODE_DEF(AnonymousStructDecl)
SWC_NODE_DEF(AnonymousUnionDecl)

// Declarations & Implementations
SWC_NODE_DEF(Impl)
SWC_NODE_DEF(ImplFor)

// Enums
SWC_NODE_DEF(EnumDecl)
SWC_NODE_DEF(ImplEnum)
SWC_NODE_DEF(EnumValue)
SWC_NODE_DEF(EnumUse)

// Functions
SWC_NODE_DEF(Call)
SWC_NODE_DEF(AttrDecl)
SWC_NODE_DEF(FunctionDecl)
SWC_NODE_DEF(FunctionBody)
SWC_NODE_DEF(LambdaTypeParam)
SWC_NODE_DEF(LambdaTypeParamList)
SWC_NODE_DEF(FunctionParamList)
SWC_NODE_DEF(ClosureCapture)
SWC_NODE_DEF(ClosureCaptureList)
SWC_NODE_DEF(FunctionExpr)
SWC_NODE_DEF(ClosureExpr)
SWC_NODE_DEF(FuncParamMe)

// Parameters / Arguments
SWC_NODE_DEF(NamedArgList)
SWC_NODE_DEF(NamedArgument)
SWC_NODE_DEF(UnnamedArgList)
SWC_NODE_DEF(UnnamedArgument)
SWC_NODE_DEF(GenericParamList)
SWC_NODE_DEF(GenericValueParam)
SWC_NODE_DEF(GenericTypeParam)

// If/Else
SWC_NODE_DEF(CompilerIf)
SWC_NODE_DEF(CompilerElse)
SWC_NODE_DEF(CompilerElseIf)

// Attributes
SWC_NODE_DEF(Attribute)
SWC_NODE_DEF(AttributeList)

// Variables / Constants
SWC_NODE_DEF(VarDecl)
SWC_NODE_DEF(VarMultiNameDecl)
SWC_NODE_DEF(VarMultiDecl)
SWC_NODE_DEF(DecompositionDecl)
SWC_NODE_DEF(Undefined)