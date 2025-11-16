// Sentinel
SWC_NODE_DEF(Invalid)

// -----------------------------------------------------------------------------
//  Program & Module Structure
// -----------------------------------------------------------------------------
SWC_NODE_DEF(File)
SWC_NODE_DEF(TopLevelBlock)
SWC_NODE_DEF(EmbeddedBlock)
SWC_NODE_DEF(Namespace)
SWC_NODE_DEF(UsingNamespace)
SWC_NODE_DEF(UsingDecl)
SWC_NODE_DEF(UsingVarDecl)
SWC_NODE_DEF(Dependencies)
SWC_NODE_DEF(Alias)
SWC_NODE_DEF(AccessModifier)
SWC_NODE_DEF(ConstraintBlock)
SWC_NODE_DEF(ConstraintExpr)
SWC_NODE_DEF(InterfaceDecl)
SWC_NODE_DEF(InterfaceBody)

// -----------------------------------------------------------------------------
//  Declarations
// -----------------------------------------------------------------------------

// Structs & Unions
SWC_NODE_DEF(AggregateBody)
SWC_NODE_DEF(StructDecl)
SWC_NODE_DEF(UnionDecl)
SWC_NODE_DEF(AnonymousStructDecl)
SWC_NODE_DEF(AnonymousUnionDecl)

// Enums
SWC_NODE_DEF(EnumDecl)
SWC_NODE_DEF(EnumBody)
SWC_NODE_DEF(EnumValue)
SWC_NODE_DEF(EnumUse)
SWC_NODE_DEF(ImplEnum)

// Implementations
SWC_NODE_DEF(Impl)
SWC_NODE_DEF(ImplFor)

// Functions
SWC_NODE_DEF(AttrDecl)
SWC_NODE_DEF(FunctionDecl)
SWC_NODE_DEF(FunctionBody)

// Variables / Constants
SWC_NODE_DEF(VarDecl)
SWC_NODE_DEF(VarMultiNameDecl)
SWC_NODE_DEF(VarMultiDecl)
SWC_NODE_DEF(VarDecompositionDecl)
SWC_NODE_DEF(Undefined)

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
SWC_NODE_DEF(RetValType)
SWC_NODE_DEF(CodeType)
SWC_NODE_DEF(VariadicType)
SWC_NODE_DEF(TypedVariadicType)

// -----------------------------------------------------------------------------
//  Identifiers & Name Resolution
// -----------------------------------------------------------------------------
SWC_NODE_DEF(Identifier)
SWC_NODE_DEF(PreQualifiedIdentifier)
SWC_NODE_DEF(AncestorIdentifier)
SWC_NODE_DEF(SuffixIdentifier)
SWC_NODE_DEF(MultiSuffixIdentifier)
SWC_NODE_DEF(ScopeResolution)

// -----------------------------------------------------------------------------
//  Parameters, Arguments & Generics
// -----------------------------------------------------------------------------
SWC_NODE_DEF(FunctionParamList)
SWC_NODE_DEF(FuncParamMe)
SWC_NODE_DEF(LambdaTypeParam)
SWC_NODE_DEF(NamedArgList)
SWC_NODE_DEF(NamedArgument)
SWC_NODE_DEF(UnnamedArgList)
SWC_NODE_DEF(UnnamedArgument)
SWC_NODE_DEF(GenericParamList)
SWC_NODE_DEF(GenericTypeParam)
SWC_NODE_DEF(GenericValueParam)

// -----------------------------------------------------------------------------
//  Expressions
// -----------------------------------------------------------------------------

// Primary & Grouping
SWC_NODE_DEF(ParenExpr)
SWC_NODE_DEF(InitializerExpr)
SWC_NODE_DEF(RangeExpr)

// Unary, Binary, Logical, Relational
SWC_NODE_DEF(UnaryExpr)
SWC_NODE_DEF(BinaryExpr)
SWC_NODE_DEF(LogicalExpr)
SWC_NODE_DEF(RelationalExpr)
SWC_NODE_DEF(BinaryConditionalExpr)
SWC_NODE_DEF(ConditionalExpr)

// Postfix
SWC_NODE_DEF(IndexExpr)
SWC_NODE_DEF(MultiIndexExpr)
SWC_NODE_DEF(StructInitializerList)

// Function Calls & Lambdas
SWC_NODE_DEF(Call)
SWC_NODE_DEF(AliasCall)
SWC_NODE_DEF(FunctionExpr)
SWC_NODE_DEF(ClosureExpr)
SWC_NODE_DEF(Discard)

// Exceptional
SWC_NODE_DEF(TryCatchAssumeExpr)

// -----------------------------------------------------------------------------
//  Type Casting & Checks
// -----------------------------------------------------------------------------
SWC_NODE_DEF(ExplicitCastExpr)
SWC_NODE_DEF(AutoCastExpr)
SWC_NODE_DEF(AsCastExpr)
SWC_NODE_DEF(IsTypeExpr)

// -----------------------------------------------------------------------------
//  Literals
// -----------------------------------------------------------------------------
SWC_NODE_DEF(BoolLiteral)
SWC_NODE_DEF(CharacterLiteral)
SWC_NODE_DEF(FloatLiteral)
SWC_NODE_DEF(IntegerLiteral)
SWC_NODE_DEF(NullLiteral)
SWC_NODE_DEF(StringLiteral)
SWC_NODE_DEF(ArrayLiteral)
SWC_NODE_DEF(StructLiteral)
SWC_NODE_DEF(CompilerLiteral)
SWC_NODE_DEF(SuffixLiteral)

// -----------------------------------------------------------------------------
//  Attributes
// -----------------------------------------------------------------------------
SWC_NODE_DEF(Attribute)
SWC_NODE_DEF(AttributeList)

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

// -----------------------------------------------------------------------------
//  Intrinsics/Compiler calls
// -----------------------------------------------------------------------------
SWC_NODE_DEF(InternalCallZero)
SWC_NODE_DEF(InternalCallUnary)
SWC_NODE_DEF(InternalCallBinary)
SWC_NODE_DEF(InternalCallTernary)
SWC_NODE_DEF(InternalCallVariadic)

// -----------------------------------------------------------------------------
//  Intrinsics
// -----------------------------------------------------------------------------
SWC_NODE_DEF(IntrinsicValue)
SWC_NODE_DEF(IntrinsicInit)
SWC_NODE_DEF(IntrinsicDrop)
SWC_NODE_DEF(IntrinsicPostCopy)
SWC_NODE_DEF(IntrinsicPostMove)

// -----------------------------------------------------------------------------
//  Control Flow & Statements
// -----------------------------------------------------------------------------

// Affect
SWC_NODE_DEF(AffectStmt)
SWC_NODE_DEF(MultiAffect)

// Conditionals (runtime)
SWC_NODE_DEF(IfStmt)
SWC_NODE_DEF(ElseIfStmt)
SWC_NODE_DEF(ElseStmt)
SWC_NODE_DEF(IfVarDecl)

// Loops
SWC_NODE_DEF(WhileStmt)
SWC_NODE_DEF(ForeachStmt)
SWC_NODE_DEF(ForCppStmt)
SWC_NODE_DEF(ForLoopStmt)
SWC_NODE_DEF(ForInfiniteStmt)

// Switch
SWC_NODE_DEF(SwitchStmt)
SWC_NODE_DEF(SwitchCaseStmt)

// Compiler Conditionals
SWC_NODE_DEF(CompilerIf)
SWC_NODE_DEF(CompilerElseIf)
SWC_NODE_DEF(CompilerElse)

// Exception Handling
SWC_NODE_DEF(TryCatch)
SWC_NODE_DEF(Throw)

// Returns
SWC_NODE_DEF(Return)

// Jumps & Flow
SWC_NODE_DEF(BreakStmt)
SWC_NODE_DEF(ScopedBreakStmt)
SWC_NODE_DEF(ContinueStmt)
SWC_NODE_DEF(FallThroughStmt)
SWC_NODE_DEF(UnreachableStmt)

// Defer / With
SWC_NODE_DEF(DeferStmt)
SWC_NODE_DEF(WithStmt)
SWC_NODE_DEF(WithVarDecl)

// Closures
SWC_NODE_DEF(ClosureCapture)
