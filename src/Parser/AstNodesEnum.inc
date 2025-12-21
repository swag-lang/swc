// ============================================================================
//  Sentinel
// ============================================================================
SWC_NODE_DEF(Invalid,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Compilation Units, Scopes & Modules
// ============================================================================
SWC_NODE_DEF(File,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(TopLevelBlock,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(EmbeddedBlock,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(DependenciesBlock,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(NamespaceDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ScopeResolution,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AccessModifier,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UsingNamespaceStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UsingDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AliasDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Identifiers & Name Resolution
// ============================================================================
SWC_NODE_DEF(Identifier,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ScopedIdentifier,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AncestorIdentifier,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IdentifierSuffix,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IdentifierSuffixList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Types
// ============================================================================
SWC_NODE_DEF(NamedType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(QualifiedType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(BuiltinType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(PointerType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(BlockPointerType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(LRefType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(RRefType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(SliceType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ArrayType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(LambdaType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(LambdaTypeParam,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(RetValType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CodeType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(VariadicType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(TypedVariadicType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ValueType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Attributes & Constraints
// ============================================================================
SWC_NODE_DEF(AttrDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(Attribute,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AttributeList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ConstraintBlock,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ConstraintExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Generics, Parameters & Arguments
// ============================================================================
SWC_NODE_DEF(GenericParamList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(GenericParamType,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(GenericParamValue,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionParamList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionParamMe,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(NamedArgumentList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(NamedArgument,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UnnamedArgumentList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UnnamedArgument,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Type, Trait & Data Declarations
// ============================================================================

// Interfaces
SWC_NODE_DEF(InterfaceDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(InterfaceBody,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Structs & Unions
SWC_NODE_DEF(AggregateBody,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(StructDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UnionDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AnonymousStructDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AnonymousUnionDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UsingMemberDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Enums
SWC_NODE_DEF(EnumDecl,
                AstNodeIdFlagsE::SemaJob,
                SemaScopeFlagsE::Type)
SWC_NODE_DEF(EnumBody,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(EnumValue,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ImplEnum,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UsingEnumDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Implementations
SWC_NODE_DEF(Impl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ImplFor,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Functions & Callables
// ============================================================================
SWC_NODE_DEF(FunctionDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionBody,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ClosureExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ClosureArgument,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Variables / Bindings
// ============================================================================
SWC_NODE_DEF(VarDecl,
                AstNodeIdFlagsE::SemaJob,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(VarDeclNameList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(VarDeclList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(VarDeclDecomposition,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IfVarDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(WithVarDecl,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

SWC_NODE_DEF(InitializerExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UndefinedExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Expressions
// ============================================================================

// Primary & Grouping
SWC_NODE_DEF(ParenExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(RangeExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Unary, Binary, Logical, Relational & Conditional
SWC_NODE_DEF(UnaryExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(LogicalExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(RelationalExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryConditionalExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ConditionalExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Postfix, Indexing & Aggregate Init
SWC_NODE_DEF(IndexExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IndexListExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(StructInitializerList,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Function Calls & Alias Calls
SWC_NODE_DEF(CallExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AliasCallExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(DiscardExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Type Casting & Type Checks
SWC_NODE_DEF(ExplicitCastExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ImplicitCastExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AutoCastExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AsCastExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IsTypeExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Exception Expressions
SWC_NODE_DEF(TryCatchExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ThrowExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Literals
// ============================================================================
SWC_NODE_DEF(BoolLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CharacterLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(FloatLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntegerLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(HexaLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(NullLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(StringLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ArrayLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(StructLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(SuffixLiteral,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Compiler Directives & Meta
// ============================================================================
SWC_NODE_DEF(CompilerDiagnostic,
                AstNodeIdFlagsE::SemaJob,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerExpression,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerCallUnary,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerRunBlock,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerRunExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerCodeBlock,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerCodeExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerFunc,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerShortFunc,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerMessageFunc,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerTypeExpr,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerGlobal,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerImport,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerScope,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerMacro,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerInject,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Compiler Conditionals
SWC_NODE_DEF(CompilerIf,
                AstNodeIdFlagsE::SemaJob,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerElse,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Intrinsics / Internal Calls
// ============================================================================

// Low-level intrinsic values & hooks
SWC_NODE_DEF(IntrinsicValue,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicInit,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicDrop,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicPostCopy,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicPostMove,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Internal compiler calls
SWC_NODE_DEF(IntrinsicCallZero,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallUnary,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallBinary,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallTernary,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallVariadic,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// ============================================================================
//  Statements & Control Flow
// ============================================================================

// Assignment / Affect
SWC_NODE_DEF(AssignStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(AssignListStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Conditionals
SWC_NODE_DEF(IfStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ElseIfStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ElseStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Loops
SWC_NODE_DEF(WhileStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ForeachStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ForCStyleStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ForStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(InfiniteLoopStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Switch
SWC_NODE_DEF(SwitchStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(SwitchCaseStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Exceptions
SWC_NODE_DEF(TryCatchStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Returns
SWC_NODE_DEF(ReturnStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Jumps & Flow Control
SWC_NODE_DEF(BreakStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ScopedBreakStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(ContinueStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(FallThroughStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(UnreachableStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)

// Defer / With
SWC_NODE_DEF(DeferStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
SWC_NODE_DEF(WithStmt,
                AstNodeIdFlagsE::Zero,
                SemaScopeFlagsE::Zero)
