// Sentinel
SWC_NODE_DEF(Invalid, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Root, Files & Module / Namespace Structure
// -----------------------------------------------------------------------------
SWC_NODE_DEF(File, ScopeFlagsE::TopLevel)
SWC_NODE_DEF(TopLevelBlock, ScopeFlagsE::Zero)
SWC_NODE_DEF(EmbeddedBlock, ScopeFlagsE::Zero)
SWC_NODE_DEF(DependenciesBlock, ScopeFlagsE::Zero)
SWC_NODE_DEF(NamespaceDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(UsingNamespaceStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(UsingDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(AliasStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(AccessModifier, ScopeFlagsE::Zero)
SWC_NODE_DEF(ScopeResolution, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Identifiers & Name Resolution
// -----------------------------------------------------------------------------
SWC_NODE_DEF(Identifier, ScopeFlagsE::Zero)
SWC_NODE_DEF(ScopedIdentifier, ScopeFlagsE::Zero)
SWC_NODE_DEF(AncestorIdentifier, ScopeFlagsE::Zero)
SWC_NODE_DEF(IdentifierSuffix, ScopeFlagsE::Zero)
SWC_NODE_DEF(IdentifierSuffixList, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Types
// -----------------------------------------------------------------------------
SWC_NODE_DEF(NamedType, ScopeFlagsE::Zero)
SWC_NODE_DEF(QualifiedType, ScopeFlagsE::Zero)
SWC_NODE_DEF(BuiltinType, ScopeFlagsE::Zero)
SWC_NODE_DEF(PointerType, ScopeFlagsE::Zero)
SWC_NODE_DEF(BlockPointerType, ScopeFlagsE::Zero)
SWC_NODE_DEF(LRefType, ScopeFlagsE::Zero)
SWC_NODE_DEF(RRefType, ScopeFlagsE::Zero)
SWC_NODE_DEF(SliceType, ScopeFlagsE::Zero)
SWC_NODE_DEF(ArrayType, ScopeFlagsE::Zero)
SWC_NODE_DEF(LambdaType, ScopeFlagsE::Zero)
SWC_NODE_DEF(LambdaTypeParam, ScopeFlagsE::Zero)
SWC_NODE_DEF(RetValType, ScopeFlagsE::Zero)
SWC_NODE_DEF(CodeType, ScopeFlagsE::Zero)
SWC_NODE_DEF(VariadicType, ScopeFlagsE::Zero)
SWC_NODE_DEF(TypedVariadicType, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Attributes & Constraints
// -----------------------------------------------------------------------------
SWC_NODE_DEF(AttrDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(Attribute, ScopeFlagsE::Zero)
SWC_NODE_DEF(AttributeList, ScopeFlagsE::Zero)
SWC_NODE_DEF(ConstraintBlock, ScopeFlagsE::Zero)
SWC_NODE_DEF(ConstraintExpr, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Generics, Parameters & Arguments
// -----------------------------------------------------------------------------
SWC_NODE_DEF(GenericParamList, ScopeFlagsE::Zero)
SWC_NODE_DEF(GenericParamType, ScopeFlagsE::Zero)
SWC_NODE_DEF(GenericParamValue, ScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionParamList, ScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionParamMe, ScopeFlagsE::Zero)
SWC_NODE_DEF(NamedArgumentList, ScopeFlagsE::Zero)
SWC_NODE_DEF(NamedArgument, ScopeFlagsE::Zero)
SWC_NODE_DEF(UnnamedArgumentList, ScopeFlagsE::Zero)
SWC_NODE_DEF(UnnamedArgument, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Type & Trait Declarations
// -----------------------------------------------------------------------------

// Interfaces
SWC_NODE_DEF(InterfaceDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(InterfaceBody, ScopeFlagsE::Zero)

// Structs & Unions
SWC_NODE_DEF(AggregateBody, ScopeFlagsE::Zero)
SWC_NODE_DEF(StructDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(UnionDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(AnonymousStructDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(AnonymousUnionDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(UsingMemberDecl, ScopeFlagsE::Zero)

// Enums
SWC_NODE_DEF(EnumDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(EnumBody, ScopeFlagsE::Zero)
SWC_NODE_DEF(EnumValue, ScopeFlagsE::Zero)
SWC_NODE_DEF(ImplEnum, ScopeFlagsE::Zero)
SWC_NODE_DEF(UsingEnumDecl, ScopeFlagsE::Zero)

// Implementations
SWC_NODE_DEF(Impl, ScopeFlagsE::Zero)
SWC_NODE_DEF(ImplFor, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Functions & Callables
// -----------------------------------------------------------------------------
SWC_NODE_DEF(FunctionDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionBody, ScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(ClosureExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(ClosureArgument, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Variables / Bindings
// -----------------------------------------------------------------------------
SWC_NODE_DEF(VarDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(VarNameListDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(VarDeclList, ScopeFlagsE::Zero)
SWC_NODE_DEF(VarDecompositionDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(IfVarDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(WithVarDecl, ScopeFlagsE::Zero)
SWC_NODE_DEF(UndefinedExpr, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Expressions
// -----------------------------------------------------------------------------

// Primary & Grouping
SWC_NODE_DEF(ParenExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(InitializerExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(RangeExpr, ScopeFlagsE::Zero)

// Unary, Binary, Logical, Relational & Conditional
SWC_NODE_DEF(UnaryExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(LogicalExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(RelationalExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryConditionalExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(ConditionalExpr, ScopeFlagsE::Zero)

// Postfix, Indexing & Aggregate Init
SWC_NODE_DEF(IndexExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(IndexListExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(StructInitializerList, ScopeFlagsE::Zero)

// Function Calls & Alias Calls
SWC_NODE_DEF(CallExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(AliasCallExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(DiscardExpr, ScopeFlagsE::Zero)

// Type Casting & Type Checks
SWC_NODE_DEF(ExplicitCastExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(AutoCastExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(AsCastExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(IsTypeExpr, ScopeFlagsE::Zero)

// Exception Expressions
SWC_NODE_DEF(TryCatchExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(ThrowExpr, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Literals
// -----------------------------------------------------------------------------
SWC_NODE_DEF(BoolLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(CharacterLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(FloatLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntegerLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(HexaLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(NullLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(StringLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(ArrayLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(StructLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerLiteral, ScopeFlagsE::Zero)
SWC_NODE_DEF(SuffixLiteral, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Compiler Directives & Meta
// -----------------------------------------------------------------------------
SWC_NODE_DEF(CompilerExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerFunc, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerShortFunc, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerEmbeddedFunc, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerMessageFunc, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerTypeExpr, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerGlobal, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerImport, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerScope, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerMacro, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerInject, ScopeFlagsE::Zero)

// Compiler Conditionals
SWC_NODE_DEF(CompilerIf, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerElse, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Intrinsics / Internal Calls
// -----------------------------------------------------------------------------

// Low-level intrinsic values & hooks
SWC_NODE_DEF(IntrinsicValue, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicInit, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicDrop, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicPostCopy, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicPostMove, ScopeFlagsE::Zero)

// Internal compiler calls
SWC_NODE_DEF(CompilerCallUnary, ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerDiagnostic, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallZero, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallUnary, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallBinary, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallTernary, ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallVariadic, ScopeFlagsE::Zero)

// -----------------------------------------------------------------------------
//  Statements & Control Flow
// -----------------------------------------------------------------------------

// Assignment / Affect
SWC_NODE_DEF(AssignStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(AssignListStmt, ScopeFlagsE::Zero)

// Conditionals (runtime, ScopeFlagsE::Zero)
SWC_NODE_DEF(IfStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(ElseIfStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(ElseStmt, ScopeFlagsE::Zero)

// Loops
SWC_NODE_DEF(WhileStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(ForeachStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(ForCStyleStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(ForStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(InfiniteLoopStmt, ScopeFlagsE::Zero)

// Switch
SWC_NODE_DEF(SwitchStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(SwitchCaseStmt, ScopeFlagsE::Zero)

// Exceptions (statement forms, ScopeFlagsE::Zero)
SWC_NODE_DEF(TryCatchStmt, ScopeFlagsE::Zero)

// Returns
SWC_NODE_DEF(ReturnStmt, ScopeFlagsE::Zero)

// Jumps & Flow Control
SWC_NODE_DEF(BreakStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(ScopedBreakStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(ContinueStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(FallThroughStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(UnreachableStmt, ScopeFlagsE::Zero)

// Defer / With
SWC_NODE_DEF(DeferStmt, ScopeFlagsE::Zero)
SWC_NODE_DEF(WithStmt, ScopeFlagsE::Zero)
