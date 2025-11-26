// Sentinel
SWC_NODE_DEF(Invalid)

// -----------------------------------------------------------------------------
//  Root, Files & Module / Namespace Structure
// -----------------------------------------------------------------------------
SWC_NODE_DEF(File)
SWC_NODE_DEF(TopLevelBlock)
SWC_NODE_DEF(EmbeddedBlock)
SWC_NODE_DEF(DependenciesBlock)
SWC_NODE_DEF(NamespaceDecl)
SWC_NODE_DEF(UsingNamespaceStmt)
SWC_NODE_DEF(UsingDecl)
SWC_NODE_DEF(AliasStmt)
SWC_NODE_DEF(AccessModifier)
SWC_NODE_DEF(ScopeResolution)

// -----------------------------------------------------------------------------
//  Identifiers & Name Resolution
// -----------------------------------------------------------------------------
SWC_NODE_DEF(Identifier)
SWC_NODE_DEF(ScopedIdentifier)
SWC_NODE_DEF(AncestorIdentifier)
SWC_NODE_DEF(IdentifierSuffix)
SWC_NODE_DEF(IdentifierSuffixList)

// -----------------------------------------------------------------------------
//  Types
// -----------------------------------------------------------------------------
SWC_NODE_DEF(NamedType)
SWC_NODE_DEF(QualifiedType)
SWC_NODE_DEF(BuiltinType)
SWC_NODE_DEF(PointerType)
SWC_NODE_DEF(BlockPointerType)
SWC_NODE_DEF(LRefType)
SWC_NODE_DEF(RRefType)
SWC_NODE_DEF(SliceType)
SWC_NODE_DEF(ArrayType)
SWC_NODE_DEF(LambdaType)
SWC_NODE_DEF(LambdaTypeParam)
SWC_NODE_DEF(RetValType)
SWC_NODE_DEF(CodeType)
SWC_NODE_DEF(VariadicType)
SWC_NODE_DEF(TypedVariadicType)

// -----------------------------------------------------------------------------
//  Attributes & Constraints
// -----------------------------------------------------------------------------
SWC_NODE_DEF(AttrDecl)
SWC_NODE_DEF(Attribute)
SWC_NODE_DEF(AttributeList)
SWC_NODE_DEF(ConstraintBlock)
SWC_NODE_DEF(ConstraintExpr)

// -----------------------------------------------------------------------------
//  Generics, Parameters & Arguments
// -----------------------------------------------------------------------------
SWC_NODE_DEF(GenericParamList)
SWC_NODE_DEF(GenericParamType)
SWC_NODE_DEF(GenericParamValue)
SWC_NODE_DEF(FunctionParamList)
SWC_NODE_DEF(FunctionParamMe)
SWC_NODE_DEF(NamedArgumentList)
SWC_NODE_DEF(NamedArgument)
SWC_NODE_DEF(UnnamedArgumentList)
SWC_NODE_DEF(UnnamedArgument)

// -----------------------------------------------------------------------------
//  Type & Trait Declarations
// -----------------------------------------------------------------------------

// Interfaces
SWC_NODE_DEF(InterfaceDecl)
SWC_NODE_DEF(InterfaceBody)

// Structs & Unions
SWC_NODE_DEF(AggregateBody)
SWC_NODE_DEF(StructDecl)
SWC_NODE_DEF(UnionDecl)
SWC_NODE_DEF(AnonymousStructDecl)
SWC_NODE_DEF(AnonymousUnionDecl)
SWC_NODE_DEF(UsingMemberDecl)

// Enums
SWC_NODE_DEF(EnumDecl)
SWC_NODE_DEF(EnumBody)
SWC_NODE_DEF(EnumValue)
SWC_NODE_DEF(ImplEnum)
SWC_NODE_DEF(UsingEnumDecl)

// Implementations
SWC_NODE_DEF(Impl)
SWC_NODE_DEF(ImplFor)

// -----------------------------------------------------------------------------
//  Functions & Callables
// -----------------------------------------------------------------------------
SWC_NODE_DEF(FunctionDecl)
SWC_NODE_DEF(FunctionBody)
SWC_NODE_DEF(FunctionExpr)
SWC_NODE_DEF(ClosureExpr)
SWC_NODE_DEF(ClosureArgument)

// -----------------------------------------------------------------------------
//  Variables / Bindings
// -----------------------------------------------------------------------------
SWC_NODE_DEF(VarDecl)
SWC_NODE_DEF(VarNameListDecl)
SWC_NODE_DEF(VarDeclList)
SWC_NODE_DEF(VarDecompositionDecl)
SWC_NODE_DEF(IfVarDecl)
SWC_NODE_DEF(WithVarDecl)
SWC_NODE_DEF(UndefinedExpr)

// -----------------------------------------------------------------------------
//  Expressions
// -----------------------------------------------------------------------------

// Primary & Grouping
SWC_NODE_DEF(ParenExpr)
SWC_NODE_DEF(InitializerExpr)
SWC_NODE_DEF(RangeExpr)

// Unary, Binary, Logical, Relational & Conditional
SWC_NODE_DEF(UnaryExpr)
SWC_NODE_DEF(BinaryExpr)
SWC_NODE_DEF(LogicalExpr)
SWC_NODE_DEF(RelationalExpr)
SWC_NODE_DEF(BinaryConditionalExpr)
SWC_NODE_DEF(ConditionalExpr)

// Postfix, Indexing & Aggregate Init
SWC_NODE_DEF(IndexExpr)
SWC_NODE_DEF(IndexListExpr)
SWC_NODE_DEF(StructInitializerList)

// Function Calls & Alias Calls
SWC_NODE_DEF(CallExpr)
SWC_NODE_DEF(AliasCallExpr)
SWC_NODE_DEF(DiscardExpr)

// Type Casting & Type Checks
SWC_NODE_DEF(ExplicitCastExpr)
SWC_NODE_DEF(AutoCastExpr)
SWC_NODE_DEF(AsCastExpr)
SWC_NODE_DEF(IsTypeExpr)

// Exception Expressions
SWC_NODE_DEF(TryCatchExpr)
SWC_NODE_DEF(ThrowExpr)

// -----------------------------------------------------------------------------
//  Literals
// -----------------------------------------------------------------------------
SWC_NODE_DEF(BoolLiteral)
SWC_NODE_DEF(CharacterLiteral)
SWC_NODE_DEF(FloatLiteral)
SWC_NODE_DEF(IntegerLiteral)
SWC_NODE_DEF(BinaryLiteral)
SWC_NODE_DEF(HexaLiteral)
SWC_NODE_DEF(NullLiteral)
SWC_NODE_DEF(StringLiteral)
SWC_NODE_DEF(ArrayLiteral)
SWC_NODE_DEF(StructLiteral)
SWC_NODE_DEF(CompilerLiteral)
SWC_NODE_DEF(SuffixLiteral)

// -----------------------------------------------------------------------------
//  Compiler Directives & Meta
// -----------------------------------------------------------------------------
SWC_NODE_DEF(CompilerExpr)
SWC_NODE_DEF(CompilerFunc)
SWC_NODE_DEF(CompilerShortFunc)
SWC_NODE_DEF(CompilerEmbeddedFunc)
SWC_NODE_DEF(CompilerMessageFunc)
SWC_NODE_DEF(CompilerTypeExpr)
SWC_NODE_DEF(CompilerGlobal)
SWC_NODE_DEF(CompilerImport)
SWC_NODE_DEF(CompilerScope)
SWC_NODE_DEF(CompilerMacro)
SWC_NODE_DEF(CompilerInject)

// Compiler Conditionals
SWC_NODE_DEF(CompilerIf)
SWC_NODE_DEF(CompilerElse)

// -----------------------------------------------------------------------------
//  Intrinsics / Internal Calls
// -----------------------------------------------------------------------------

// Low-level intrinsic values & hooks
SWC_NODE_DEF(IntrinsicValue)
SWC_NODE_DEF(IntrinsicInit)
SWC_NODE_DEF(IntrinsicDrop)
SWC_NODE_DEF(IntrinsicPostCopy)
SWC_NODE_DEF(IntrinsicPostMove)

// Internal compiler calls
SWC_NODE_DEF(CompilerCallUnary)
SWC_NODE_DEF(CompilerDiagnostic)
SWC_NODE_DEF(IntrinsicCallZero)
SWC_NODE_DEF(IntrinsicCallUnary)
SWC_NODE_DEF(IntrinsicCallBinary)
SWC_NODE_DEF(IntrinsicCallTernary)
SWC_NODE_DEF(IntrinsicCallVariadic)

// -----------------------------------------------------------------------------
//  Statements & Control Flow
// -----------------------------------------------------------------------------

// Assignment / Affect
SWC_NODE_DEF(AssignStmt)
SWC_NODE_DEF(AssignListStmt)

// Conditionals (runtime)
SWC_NODE_DEF(IfStmt)
SWC_NODE_DEF(ElseIfStmt)
SWC_NODE_DEF(ElseStmt)

// Loops
SWC_NODE_DEF(WhileStmt)
SWC_NODE_DEF(ForeachStmt)
SWC_NODE_DEF(ForCStyleStmt)
SWC_NODE_DEF(ForStmt)
SWC_NODE_DEF(InfiniteLoopStmt)

// Switch
SWC_NODE_DEF(SwitchStmt)
SWC_NODE_DEF(SwitchCaseStmt)

// Exceptions (statement forms)
SWC_NODE_DEF(TryCatchStmt)

// Returns
SWC_NODE_DEF(ReturnStmt)

// Jumps & Flow Control
SWC_NODE_DEF(BreakStmt)
SWC_NODE_DEF(ScopedBreakStmt)
SWC_NODE_DEF(ContinueStmt)
SWC_NODE_DEF(FallThroughStmt)
SWC_NODE_DEF(UnreachableStmt)

// Defer / With
SWC_NODE_DEF(DeferStmt)
SWC_NODE_DEF(WithStmt)
