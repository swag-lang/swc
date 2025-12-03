// ============================================================================
//  Sentinel
// ============================================================================
SWC_NODE_DEF(Invalid,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Compilation Units, Scopes & Modules
// ============================================================================
SWC_NODE_DEF(File,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::TopLevel)
SWC_NODE_DEF(TopLevelBlock,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(EmbeddedBlock,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(DependenciesBlock,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(NamespaceDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ScopeResolution,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AccessModifier,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UsingNamespaceStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UsingDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AliasDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Identifiers & Name Resolution
// ============================================================================
SWC_NODE_DEF(Identifier,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ScopedIdentifier,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AncestorIdentifier,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IdentifierSuffix,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IdentifierSuffixList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Types
// ============================================================================
SWC_NODE_DEF(NamedType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(QualifiedType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(BuiltinType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(PointerType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(BlockPointerType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(LRefType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(RRefType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(SliceType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ArrayType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(LambdaType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(LambdaTypeParam,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(RetValType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CodeType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(VariadicType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(TypedVariadicType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Attributes & Constraints
// ============================================================================
SWC_NODE_DEF(AttrDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(Attribute,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AttributeList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ConstraintBlock,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ConstraintExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Generics, Parameters & Arguments
// ============================================================================
SWC_NODE_DEF(GenericParamList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(GenericParamType,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(GenericParamValue,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionParamList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionParamMe,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(NamedArgumentList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(NamedArgument,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UnnamedArgumentList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UnnamedArgument,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Type, Trait & Data Declarations
// ============================================================================

// Interfaces
SWC_NODE_DEF(InterfaceDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(InterfaceBody,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Structs & Unions
SWC_NODE_DEF(AggregateBody,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(StructDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UnionDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AnonymousStructDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AnonymousUnionDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UsingMemberDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Enums
SWC_NODE_DEF(EnumDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(EnumBody,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(EnumValue,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ImplEnum,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UsingEnumDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Implementations
SWC_NODE_DEF(Impl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ImplFor,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Functions & Callables
// ============================================================================
SWC_NODE_DEF(FunctionDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionBody,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(FunctionExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ClosureExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ClosureArgument,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Variables / Bindings
// ============================================================================
SWC_NODE_DEF(VarDecl,
                AstNodeIdFlagsE::SemaJob,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(VarDeclNameList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(VarDeclList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(VarDeclDecomposition,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IfVarDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(WithVarDecl,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

SWC_NODE_DEF(InitializerExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UndefinedExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Expressions
// ============================================================================

// Primary & Grouping
SWC_NODE_DEF(ParenExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(RangeExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Unary, Binary, Logical, Relational & Conditional
SWC_NODE_DEF(UnaryExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(LogicalExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(RelationalExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryConditionalExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ConditionalExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Postfix, Indexing & Aggregate Init
SWC_NODE_DEF(IndexExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IndexListExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(StructInitializerList,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Function Calls & Alias Calls
SWC_NODE_DEF(CallExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AliasCallExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(DiscardExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Type Casting & Type Checks
SWC_NODE_DEF(ExplicitCastExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AutoCastExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AsCastExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IsTypeExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Exception Expressions
SWC_NODE_DEF(TryCatchExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ThrowExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Literals
// ============================================================================
SWC_NODE_DEF(BoolLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CharacterLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(FloatLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntegerLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(BinaryLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(HexaLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(NullLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(StringLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ArrayLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(StructLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(SuffixLiteral,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Compiler Directives & Meta
// ============================================================================
SWC_NODE_DEF(CompilerDiagnostic,
                AstNodeIdFlagsE::SemaJob,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerExpression,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerCallUnary,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerRunBlock,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerRunExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerCodeBlock,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerCodeExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerFunc,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerShortFunc,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerMessageFunc,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerTypeExpr,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerGlobal,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerImport,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerScope,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerMacro,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerInject,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Compiler Conditionals
SWC_NODE_DEF(CompilerIf,
                AstNodeIdFlagsE::SemaJob,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(CompilerElse,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Intrinsics / Internal Calls
// ============================================================================

// Low-level intrinsic values & hooks
SWC_NODE_DEF(IntrinsicValue,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicInit,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicDrop,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicPostCopy,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicPostMove,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Internal compiler calls
SWC_NODE_DEF(IntrinsicCallZero,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallUnary,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallBinary,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallTernary,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallVariadic,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// ============================================================================
//  Statements & Control Flow
// ============================================================================

// Assignment / Affect
SWC_NODE_DEF(AssignStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(AssignListStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Conditionals
SWC_NODE_DEF(IfStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ElseIfStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ElseStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Loops
SWC_NODE_DEF(WhileStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ForeachStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ForCStyleStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ForStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(InfiniteLoopStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Switch
SWC_NODE_DEF(SwitchStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(SwitchCaseStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Exceptions
SWC_NODE_DEF(TryCatchStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Returns
SWC_NODE_DEF(ReturnStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Jumps & Flow Control
SWC_NODE_DEF(BreakStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ScopedBreakStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(ContinueStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(FallThroughStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(UnreachableStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)

// Defer / With
SWC_NODE_DEF(DeferStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
SWC_NODE_DEF(WithStmt,
                AstNodeIdFlagsE::Zero,
                ScopeFlagsE::Zero)
