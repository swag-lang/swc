// ============================================================================
//  Sentinel
// ============================================================================
SWC_NODE_DEF(Invalid, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Compilation Units, Scopes & Modules
// ============================================================================
SWC_NODE_DEF(File, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(TopLevelBlock, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(EmbeddedBlock, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(DependenciesBlock, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(NamespaceDecl, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(AutoMemberAccessExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(MemberAccessExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AccessModifier, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(UsingNamespaceStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(UsingDecl, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AliasDecl, AstNodeIdFlagsE::SemaJob)

// ============================================================================
//  Identifiers & Name Resolution
// ============================================================================
SWC_NODE_DEF(Identifier, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AncestorIdentifier, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(QuotedExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(QuotedListExpr, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Types
// ============================================================================
SWC_NODE_DEF(NamedType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(QualifiedType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(BuiltinType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ValuePointerType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(BlockPointerType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(LRefType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(RRefType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(SliceType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ArrayType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(LambdaType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(RetValType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CodeType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(VariadicType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(TypedVariadicType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ValueType, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Attributes & Constraints
// ============================================================================
SWC_NODE_DEF(AttrDecl, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(Attribute, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AttributeList, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(ConstraintBlock, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ConstraintExpr, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Generics, Parameters & Arguments
// ============================================================================
SWC_NODE_DEF(GenericParamList, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(GenericParamType, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(GenericParamValue, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(FunctionParamList, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(FunctionParamMe, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(NamedArgumentList, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(NamedArgument, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(UnnamedArgumentList, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(UnnamedArgument, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(LambdaParam, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Type, Trait & Data Declarations
// ============================================================================

// Interfaces
SWC_NODE_DEF(InterfaceDecl, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(InterfaceBody, AstNodeIdFlagsE::Zero)

// Structs & Unions
SWC_NODE_DEF(AggregateBody, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(StructDecl, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(UnionDecl, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(AnonymousStructDecl, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AnonymousUnionDecl, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(UsingMemberDecl, AstNodeIdFlagsE::Zero)

// Enums
SWC_NODE_DEF(EnumDecl, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(EnumBody, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(EnumValue, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(UsingEnumDecl, AstNodeIdFlagsE::Zero)

// Implementations
SWC_NODE_DEF(Impl, AstNodeIdFlagsE::SemaJob)

// ============================================================================
//  Functions & Callables
// ============================================================================
SWC_NODE_DEF(FunctionDecl, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(FunctionBody, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(FunctionExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ClosureExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ClosureArgument, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Variables / Bindings
// ============================================================================
SWC_NODE_DEF(VarDecl, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(VarDeclNameList, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(VarDeclList, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(VarDeclDecomposition, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(IfVarDecl, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(WithVarDecl, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(InitializerExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(UndefinedExpr, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Expressions
// ============================================================================
SWC_NODE_DEF(ParenExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(RangeExpr, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(UnaryExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(BinaryExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(LogicalExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(RelationalExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(BinaryConditionalExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ConditionalExpr, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(IndexExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(IndexListExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(StructInitializerList, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(CallExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AliasCallExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(DiscardExpr, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(ExplicitCastExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ImplicitCastExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AutoCastExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AsCastExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(IsTypeExpr, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(TryCatchExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ThrowExpr, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Literals
// ============================================================================
SWC_NODE_DEF(BoolLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CharacterLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(FloatLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(IntegerLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(BinaryLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(HexaLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(NullLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(StringLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ArrayLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(StructLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerLiteral, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(SuffixLiteral, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Compiler Directives & Meta
// ============================================================================
SWC_NODE_DEF(CompilerDiagnostic, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(CompilerExpression, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerCall, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerRunBlock, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerRunExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerCodeBlock, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerCodeExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerFunc, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(CompilerShortFunc, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerMessageFunc, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerTypeExpr, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerGlobal, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerImport, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerScope, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerMacro, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(CompilerInject, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(CompilerIf, AstNodeIdFlagsE::SemaJob)
SWC_NODE_DEF(CompilerElse, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Intrinsics / Internal Calls
// ============================================================================
SWC_NODE_DEF(IntrinsicValue, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(IntrinsicInit, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(IntrinsicDrop, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(IntrinsicPostCopy, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(IntrinsicPostMove, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(IntrinsicCall, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(IntrinsicCallVariadic, AstNodeIdFlagsE::Zero)

// ============================================================================
//  Statements & Control Flow
// ============================================================================
SWC_NODE_DEF(AssignStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(AssignListStmt, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(IfStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ElseIfStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ElseStmt, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(WhileStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ForeachStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ForCStyleStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ForStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(InfiniteLoopStmt, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(SwitchStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(SwitchCaseStmt, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(TryCatchStmt, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(ReturnStmt, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(BreakStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ScopedBreakStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(ContinueStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(FallThroughStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(UnreachableStmt, AstNodeIdFlagsE::Zero)

SWC_NODE_DEF(DeferStmt, AstNodeIdFlagsE::Zero)
SWC_NODE_DEF(WithStmt, AstNodeIdFlagsE::Zero)
