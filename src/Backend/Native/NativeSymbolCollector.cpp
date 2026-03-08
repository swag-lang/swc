#include "pch.h"
#include "Backend/Native/NativeSymbolCollector.h"

SWC_BEGIN_NAMESPACE();

NativeSymbolCollector::NativeSymbolCollector(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

bool NativeSymbolCollector::prepare()
{
    if (!collectSymbols())
        return false;
    return scheduleCodeGen();
}

bool NativeSymbolCollector::collectSymbols()
{
    auto& compiler = builder_.compiler();
    auto& state    = builder_.state();

    compiler.resetNativeCodeSegment();
    state.rawFunctions.clear();
    state.rawTestFunctions.clear();
    state.rawInitFunctions.clear();
    state.rawPreMainFunctions.clear();
    state.rawDropFunctions.clear();
    state.rawMainFunctions.clear();
    state.regularGlobals.clear();
    state.functionInfos.clear();
    state.functionBySymbol.clear();

    const SymbolModule* rootModule = compiler.symModule();
    if (!rootModule)
        return builder_.reportError(DiagnosticId::cmd_err_native_root_module_missing);

    collectSymbolsRec(*rootModule);

    sortAndUnique(state.rawFunctions);
    sortAndUnique(state.rawTestFunctions);
    sortAndUnique(state.rawInitFunctions);
    sortAndUnique(state.rawPreMainFunctions);
    sortAndUnique(state.rawDropFunctions);
    sortAndUnique(state.rawMainFunctions);
    sortAndUnique(state.regularGlobals);

    for (SymbolFunction* symbol : state.rawFunctions)
    {
        compiler.addNativeCodeFunction(symbol);

        NativeFunctionInfo info;
        info.symbol      = symbol;
        info.machineCode = &symbol->loweredCode();
        info.sortKey     = makeSymbolSortKey(*symbol);
        info.symbolName  = std::format("__swc_fn_{:06}_{:08x}", state.functionInfos.size(), Math::hash(info.sortKey));
        info.exported    = symbol->isPublic() && !isCompilerFunction(*symbol);
        info.compilerFn  = isCompilerFunction(*symbol);
        state.functionInfos.push_back(std::move(info));
    }

    for (const auto& info : state.functionInfos)
        state.functionBySymbol.emplace(info.symbol, &info);

    for (SymbolFunction* symbol : state.rawTestFunctions)
        compiler.addNativeTestFunction(symbol);
    for (SymbolFunction* symbol : state.rawInitFunctions)
        compiler.addNativeInitFunction(symbol);
    for (SymbolFunction* symbol : state.rawPreMainFunctions)
        compiler.addNativePreMainFunction(symbol);
    for (SymbolFunction* symbol : state.rawDropFunctions)
        compiler.addNativeDropFunction(symbol);
    for (SymbolFunction* symbol : state.rawMainFunctions)
        compiler.addNativeMainFunction(symbol);

    return true;
}

void NativeSymbolCollector::collectSymbolsRec(const SymbolMap& symbolMap)
{
    std::vector<const Symbol*> symbols;
    symbolMap.getAllSymbols(symbols);
    for (const Symbol* symbol : symbols)
    {
        if (!symbol)
            continue;

        if (symbol->isFunction())
        {
            auto* function = const_cast<SymbolFunction*>(symbol->safeCast<SymbolFunction>());
            if (function)
                collectFunction(*function);
            continue;
        }

        if (symbol->isVariable())
        {
            auto* variable = const_cast<SymbolVariable*>(symbol->safeCast<SymbolVariable>());
            if (variable && variable->hasGlobalStorage())
                builder_.state().regularGlobals.push_back(variable);
            continue;
        }

        if (symbol->kind() == SymbolKind::Module ||
            symbol->kind() == SymbolKind::Namespace ||
            symbol->kind() == SymbolKind::Struct ||
            symbol->kind() == SymbolKind::Interface ||
            symbol->kind() == SymbolKind::Impl)
        {
            collectSymbolsRec(*const_cast<SymbolMap*>(symbol->asSymMap()));
        }
    }
}

void NativeSymbolCollector::collectFunction(SymbolFunction& symbol) const
{
    if (symbol.isForeign() || symbol.isEmpty() || symbol.isAttribute())
        return;
    if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
        return;

    const CompilerFunctionKind compilerKind = classifyCompilerFunction(symbol);
    if (compilerKind == CompilerFunctionKind::Excluded)
        return;

    auto& state = builder_.state();
    state.rawFunctions.push_back(&symbol);

    switch (compilerKind)
    {
        case CompilerFunctionKind::Test:
            state.rawTestFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::Init:
            state.rawInitFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::PreMain:
            state.rawPreMainFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::Drop:
            state.rawDropFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::Main:
            state.rawMainFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::None:
        case CompilerFunctionKind::Excluded:
            break;
    }
}

bool NativeSymbolCollector::scheduleCodeGen() const
{
    const auto& state = builder_.state();
    if (state.functionInfos.empty())
        return true;

    SourceFile* firstFile = nullptr;
    for (SourceFile* file : builder_.compiler().files())
    {
        if (file)
        {
            firstFile = file;
            break;
        }
    }

    if (!firstFile)
        return builder_.reportError(DiagnosticId::cmd_err_native_codegen_source_missing);

    Sema        baseSema(builder_.ctx(), firstFile->nodePayloadContext(), false);
    JobManager& jobMgr = builder_.ctx().global().jobMgr();
    for (const auto& info : state.functionInfos)
    {
        if (!info.symbol)
            continue;
        if (info.symbol->isCodeGenCompleted() || !info.symbol->loweredCode().bytes.empty())
            continue;
        if (!info.symbol->tryMarkCodeGenJobScheduled())
            continue;

        const AstNodeRef root = info.symbol->declNodeRef();
        if (root.isInvalid())
            return builder_.reportError(DiagnosticId::cmd_err_native_codegen_decl_missing, Diagnostic::ARG_SYM, info.symbolName);

        auto* job = heapNew<CodeGenJob>(builder_.ctx(), baseSema, *info.symbol, root);
        jobMgr.enqueue(*job, JobPriority::Normal, builder_.compiler().jobClientId());
    }

    Sema::waitDone(builder_.ctx(), builder_.compiler().jobClientId());
    if (Stats::get().numErrors.load(std::memory_order_relaxed) != 0)
        return false;

    for (const auto& info : state.functionInfos)
    {
        if (!info.machineCode || info.machineCode->bytes.empty())
            return builder_.reportError(DiagnosticId::cmd_err_native_codegen_machine_code_missing, Diagnostic::ARG_SYM, info.symbolName);
    }

    return true;
}

NativeSymbolCollector::CompilerFunctionKind NativeSymbolCollector::classifyCompilerFunction(const SymbolFunction& symbol) const
{
    if (!isCompilerFunction(symbol))
        return CompilerFunctionKind::None;

    const SourceView& srcView = builder_.compiler().srcView(symbol.srcViewRef());
    const Token&      token   = srcView.token(symbol.tokRef());
    switch (token.id)
    {
        case TokenId::CompilerFuncTest:
            return CompilerFunctionKind::Test;
        case TokenId::CompilerFuncInit:
            return CompilerFunctionKind::Init;
        case TokenId::CompilerFuncPreMain:
            return CompilerFunctionKind::PreMain;
        case TokenId::CompilerFuncDrop:
            return CompilerFunctionKind::Drop;
        case TokenId::CompilerFuncMain:
            return CompilerFunctionKind::Main;
        case TokenId::CompilerRun:
        case TokenId::CompilerAst:
        case TokenId::CompilerFuncMessage:
            return CompilerFunctionKind::Excluded;
        default:
            return CompilerFunctionKind::Excluded;
    }
}

bool NativeSymbolCollector::isCompilerFunction(const SymbolFunction& symbol)
{
    return symbol.decl() && symbol.decl()->id() == AstNodeId::CompilerFunc;
}

Utf8 NativeSymbolCollector::makeSymbolSortKey(const SymbolFunction& symbol) const
{
    Utf8 key = symbol.getFullScopedName(builder_.ctx());
    key += "|";
    key += symbol.computeName(builder_.ctx());

    if (const SourceFile* file = builder_.compiler().srcView(symbol.srcViewRef()).file())
    {
        key += "|";
        key += makeUtf8(file->path());
    }

    key += "|";
    key += std::to_string(symbol.tokRef().get());
    return key;
}

Utf8 NativeSymbolCollector::makeSortKey(const SymbolFunction& symbol) const
{
    return makeSymbolSortKey(symbol);
}

Utf8 NativeSymbolCollector::makeSortKey(const SymbolVariable& symbol) const
{
    Utf8 key = symbol.getFullScopedName(builder_.ctx());
    key += "|";
    if (const SourceFile* file = builder_.compiler().srcView(symbol.srcViewRef()).file())
        key += makeUtf8(file->path());
    key += "|";
    key += std::to_string(symbol.tokRef().get());
    return key;
}

SWC_END_NAMESPACE();
