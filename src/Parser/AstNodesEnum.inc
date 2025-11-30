// clang-format off

// Sentinel
SWC_NODE_DEF(Invalid,               Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Root, Files & Module / Namespace Structure
// -----------------------------------------------------------------------------
SWC_NODE_DEF(File,                  Zero,                      TopLevel)
SWC_NODE_DEF(TopLevelBlock,         Zero,                      Zero)
SWC_NODE_DEF(EmbeddedBlock,         Zero,                      Zero)
SWC_NODE_DEF(DependenciesBlock,     Zero,                      Zero)
SWC_NODE_DEF(NamespaceDecl,         Zero,                      Zero)
SWC_NODE_DEF(UsingNamespaceStmt,    Zero,                      Zero)
SWC_NODE_DEF(UsingDecl,             Zero,                      Zero)
SWC_NODE_DEF(AliasDecl,             Zero,                      Zero)
SWC_NODE_DEF(AccessModifier,        Zero,                      Zero)
SWC_NODE_DEF(ScopeResolution,       Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Identifiers & Name Resolution
// -----------------------------------------------------------------------------
SWC_NODE_DEF(Identifier,            Zero,                      Zero)
SWC_NODE_DEF(ScopedIdentifier,      Zero,                      Zero)
SWC_NODE_DEF(AncestorIdentifier,    Zero,                      Zero)
SWC_NODE_DEF(IdentifierSuffix,      Zero,                      Zero)
SWC_NODE_DEF(IdentifierSuffixList,  Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Types
// -----------------------------------------------------------------------------
SWC_NODE_DEF(NamedType,             Zero,                      Zero)
SWC_NODE_DEF(QualifiedType,         Zero,                      Zero)
SWC_NODE_DEF(BuiltinType,           Zero,                      Zero)
SWC_NODE_DEF(PointerType,           Zero,                      Zero)
SWC_NODE_DEF(BlockPointerType,      Zero,                      Zero)
SWC_NODE_DEF(LRefType,              Zero,                      Zero)
SWC_NODE_DEF(RRefType,              Zero,                      Zero)
SWC_NODE_DEF(SliceType,             Zero,                      Zero)
SWC_NODE_DEF(ArrayType,             Zero,                      Zero)
SWC_NODE_DEF(LambdaType,            Zero,                      Zero)
SWC_NODE_DEF(LambdaTypeParam,       Zero,                      Zero)
SWC_NODE_DEF(RetValType,            Zero,                      Zero)
SWC_NODE_DEF(CodeType,              Zero,                      Zero)
SWC_NODE_DEF(VariadicType,          Zero,                      Zero)
SWC_NODE_DEF(TypedVariadicType,     Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Attributes & Constraints
// -----------------------------------------------------------------------------
SWC_NODE_DEF(AttrDecl,              Zero,                      Zero)
SWC_NODE_DEF(Attribute,             Zero,                      Zero)
SWC_NODE_DEF(AttributeList,         Zero,                      Zero)
SWC_NODE_DEF(ConstraintBlock,       Zero,                      Zero)
SWC_NODE_DEF(ConstraintExpr,        Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Generics, Parameters & Arguments
// -----------------------------------------------------------------------------
SWC_NODE_DEF(GenericParamList,      Zero,                      Zero)
SWC_NODE_DEF(GenericParamType,      Zero,                      Zero)
SWC_NODE_DEF(GenericParamValue,     Zero,                      Zero)
SWC_NODE_DEF(FunctionParamList,     Zero,                      Zero)
SWC_NODE_DEF(FunctionParamMe,       Zero,                      Zero)
SWC_NODE_DEF(NamedArgumentList,     Zero,                      Zero)
SWC_NODE_DEF(NamedArgument,         Zero,                      Zero)
SWC_NODE_DEF(UnnamedArgumentList,   Zero,                      Zero)
SWC_NODE_DEF(UnnamedArgument,       Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Type & Trait Declarations
// -----------------------------------------------------------------------------

// Interfaces
SWC_NODE_DEF(InterfaceDecl,         Zero,                      Zero)
SWC_NODE_DEF(InterfaceBody,         Zero,                      Zero)

// Structs & Unions
SWC_NODE_DEF(AggregateBody,         Zero,                      Zero)
SWC_NODE_DEF(StructDecl,            Zero,                      Zero)
SWC_NODE_DEF(UnionDecl,             Zero,                      Zero)
SWC_NODE_DEF(AnonymousStructDecl,   Zero,                      Zero)
SWC_NODE_DEF(AnonymousUnionDecl,    Zero,                      Zero)
SWC_NODE_DEF(UsingMemberDecl,       Zero,                      Zero)

// Enums
SWC_NODE_DEF(EnumDecl,              Zero,                      Zero)
SWC_NODE_DEF(EnumBody,              Zero,                      Zero)
SWC_NODE_DEF(EnumValue,             Zero,                      Zero)
SWC_NODE_DEF(ImplEnum,              Zero,                      Zero)
SWC_NODE_DEF(UsingEnumDecl,         Zero,                      Zero)

// Implementations
SWC_NODE_DEF(Impl,                  Zero,                      Zero)
SWC_NODE_DEF(ImplFor,               Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Functions & Callables
// -----------------------------------------------------------------------------
SWC_NODE_DEF(FunctionDecl,          Zero,                      Zero)
SWC_NODE_DEF(FunctionBody,          Zero,                      Zero)
SWC_NODE_DEF(FunctionExpr,          Zero,                      Zero)
SWC_NODE_DEF(ClosureExpr,           Zero,                      Zero)
SWC_NODE_DEF(ClosureArgument,       Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Variables / Bindings
// -----------------------------------------------------------------------------
SWC_NODE_DEF(VarDecl,               Zero,                      Zero)
SWC_NODE_DEF(VarNameListDecl,       Zero,                      Zero)
SWC_NODE_DEF(VarDeclList,           Zero,                      Zero)
SWC_NODE_DEF(VarDecompositionDecl,  Zero,                      Zero)
SWC_NODE_DEF(IfVarDecl,             Zero,                      Zero)
SWC_NODE_DEF(WithVarDecl,           Zero,                      Zero)
SWC_NODE_DEF(UndefinedExpr,         Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Expressions
// -----------------------------------------------------------------------------

// Primary & Grouping
SWC_NODE_DEF(ParenExpr,             Zero,                      Zero)
SWC_NODE_DEF(InitializerExpr,       Zero,                      Zero)
SWC_NODE_DEF(RangeExpr,             Zero,                      Zero)

// Unary, Binary, Logical, Relational & Conditional
SWC_NODE_DEF(UnaryExpr,             Zero,                      Zero)
SWC_NODE_DEF(BinaryExpr,            Zero,                      Zero)
SWC_NODE_DEF(LogicalExpr,           Zero,                      Zero)
SWC_NODE_DEF(RelationalExpr,        Zero,                      Zero)
SWC_NODE_DEF(BinaryConditionalExpr, Zero,                      Zero)
SWC_NODE_DEF(ConditionalExpr,       Zero,                      Zero)

// Postfix, Indexing & Aggregate Init
SWC_NODE_DEF(IndexExpr,             Zero,                      Zero)
SWC_NODE_DEF(IndexListExpr,         Zero,                      Zero)
SWC_NODE_DEF(StructInitializerList, Zero,                      Zero)

// Function Calls & Alias Calls
SWC_NODE_DEF(CallExpr,              Zero,                      Zero)
SWC_NODE_DEF(AliasCallExpr,         Zero,                      Zero)
SWC_NODE_DEF(DiscardExpr,           Zero,                      Zero)

// Type Casting & Type Checks
SWC_NODE_DEF(ExplicitCastExpr,      Zero,                      Zero)
SWC_NODE_DEF(AutoCastExpr,          Zero,                      Zero)
SWC_NODE_DEF(AsCastExpr,            Zero,                      Zero)
SWC_NODE_DEF(IsTypeExpr,            Zero,                      Zero)

// Exception Expressions
SWC_NODE_DEF(TryCatchExpr,          Zero,                      Zero)
SWC_NODE_DEF(ThrowExpr,             Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Literals
// -----------------------------------------------------------------------------
SWC_NODE_DEF(BoolLiteral,           Zero,                      Zero)
SWC_NODE_DEF(CharacterLiteral,      Zero,                      Zero)
SWC_NODE_DEF(FloatLiteral,          Zero,                      Zero)
SWC_NODE_DEF(IntegerLiteral,        Zero,                      Zero)
SWC_NODE_DEF(BinaryLiteral,         Zero,                      Zero)
SWC_NODE_DEF(HexaLiteral,           Zero,                      Zero)
SWC_NODE_DEF(NullLiteral,           Zero,                      Zero)
SWC_NODE_DEF(StringLiteral,         Zero,                      Zero)
SWC_NODE_DEF(ArrayLiteral,          Zero,                      Zero)
SWC_NODE_DEF(StructLiteral,         Zero,                      Zero)
SWC_NODE_DEF(CompilerLiteral,       Zero,                      Zero)
SWC_NODE_DEF(SuffixLiteral,         Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Compiler Directives & Meta
// -----------------------------------------------------------------------------
SWC_NODE_DEF(CompilerDiagnostic,    SemaJob,                   Zero)

SWC_NODE_DEF(CompilerCallUnary,     Zero,                      Zero)
SWC_NODE_DEF(CompilerExpr,          Zero,                      Zero)
SWC_NODE_DEF(CompilerFunc,          Zero,                      Zero)
SWC_NODE_DEF(CompilerShortFunc,     Zero,                      Zero)
SWC_NODE_DEF(CompilerEmbeddedFunc,  Zero,                      Zero)
SWC_NODE_DEF(CompilerMessageFunc,   Zero,                      Zero)
SWC_NODE_DEF(CompilerTypeExpr,      Zero,                      Zero)
SWC_NODE_DEF(CompilerGlobal,        Zero,                      Zero)
SWC_NODE_DEF(CompilerImport,        Zero,                      Zero)
SWC_NODE_DEF(CompilerScope,         Zero,                      Zero)
SWC_NODE_DEF(CompilerMacro,         Zero,                      Zero)
SWC_NODE_DEF(CompilerInject,        Zero,                      Zero)

// Compiler Conditionals
SWC_NODE_DEF(CompilerIf,            SemaJob,                   Zero)
SWC_NODE_DEF(CompilerElse,          Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Intrinsics / Internal Calls
// -----------------------------------------------------------------------------

// Low-level intrinsic values & hooks
SWC_NODE_DEF(IntrinsicValue,        Zero,                      Zero)
SWC_NODE_DEF(IntrinsicInit,         Zero,                      Zero)
SWC_NODE_DEF(IntrinsicDrop,         Zero,                      Zero)
SWC_NODE_DEF(IntrinsicPostCopy,     Zero,                      Zero)
SWC_NODE_DEF(IntrinsicPostMove,     Zero,                      Zero)

// Internal compiler calls
SWC_NODE_DEF(IntrinsicCallZero,     Zero,                      Zero)
SWC_NODE_DEF(IntrinsicCallUnary,    Zero,                      Zero)
SWC_NODE_DEF(IntrinsicCallBinary,   Zero,                      Zero)
SWC_NODE_DEF(IntrinsicCallTernary,  Zero,                      Zero)
SWC_NODE_DEF(IntrinsicCallVariadic, Zero,                      Zero)

// -----------------------------------------------------------------------------
//  Statements & Control Flow
// -----------------------------------------------------------------------------

// Assignment / Affect
SWC_NODE_DEF(AssignStmt,            Zero,                      Zero)
SWC_NODE_DEF(AssignListStmt,        Zero,                      Zero)

// Conditionals
SWC_NODE_DEF(IfStmt,                Zero,                      Zero)
SWC_NODE_DEF(ElseIfStmt,            Zero,                      Zero)
SWC_NODE_DEF(ElseStmt,              Zero,                      Zero)

// Loops
SWC_NODE_DEF(WhileStmt,             Zero,                      Zero)
SWC_NODE_DEF(ForeachStmt,           Zero,                      Zero)
SWC_NODE_DEF(ForCStyleStmt,         Zero,                      Zero)
SWC_NODE_DEF(ForStmt,               Zero,                      Zero)
SWC_NODE_DEF(InfiniteLoopStmt,      Zero,                      Zero)

// Switch
SWC_NODE_DEF(SwitchStmt,            Zero,                      Zero)
SWC_NODE_DEF(SwitchCaseStmt,        Zero,                      Zero)

// Exceptions
SWC_NODE_DEF(TryCatchStmt,          Zero,                      Zero)

// Returns
SWC_NODE_DEF(ReturnStmt,            Zero,                      Zero)

// Jumps & Flow Control
SWC_NODE_DEF(BreakStmt,             Zero,                      Zero)
SWC_NODE_DEF(ScopedBreakStmt,       Zero,                      Zero)
SWC_NODE_DEF(ContinueStmt,          Zero,                      Zero)
SWC_NODE_DEF(FallThroughStmt,       Zero,                      Zero)
SWC_NODE_DEF(UnreachableStmt,       Zero,                      Zero)

// Defer / With
SWC_NODE_DEF(DeferStmt,             Zero,                      Zero)
SWC_NODE_DEF(WithStmt,              Zero,                      Zero)
