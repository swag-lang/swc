#include "pch.h"
#include "Backend/Native/NativeSymbolCollector.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Main/Global.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()
class CodeGenJob;

NativeSymbolCollector::NativeSymbolCollector(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

Result NativeSymbolCollector::prepare()
{
    SWC_RESULT(collectSymbols());
    return scheduleCodeGen();
}

Result NativeSymbolCollector::collectSymbols()
{
    auto& compiler = builder_.compiler();

    compiler.resetNativeCodeSegment();
    builder_.rawFunctions.clear();
    builder_.rawTestFunctions.clear();
    builder_.rawInitFunctions.clear();
    builder_.rawPreMainFunctions.clear();
    builder_.rawDropFunctions.clear();
    builder_.rawMainFunctions.clear();
    builder_.regularGlobals.clear();
    builder_.functionInfos.clear();
    builder_.functionBySymbol.clear();
    seenFunctions_.clear();

    const SymbolModule* rootModule = compiler.symModule();
    if (!rootModule)
        return builder_.reportError(DiagnosticId::cmd_err_native_root_module_missing);

    collectCompilerEntryFunctions();
    collectSymbolsRec(*rootModule);
    for (const SourceFile* file : compiler.files())
    {
        if (!file)
            continue;
        if (const SymbolNamespace* fileNamespace = file->fileNamespace())
            collectGlobalVariablesRec(*fileNamespace);
    }

    for (size_t idx = 0; idx < builder_.rawFunctions.size(); ++idx) // NOLINT(modernize-loop-convert)
    {
        const SymbolFunction* function = builder_.rawFunctions[idx];
        SWC_ASSERT(function != nullptr);

        SmallVector<SymbolFunction*> deps;
        function->appendCallDependencies(deps);
        for (SymbolFunction* dep : deps)
        {
            SWC_ASSERT(dep != nullptr);
            collectFunction(*dep);
        }
    }

    sortAndUnique(builder_.rawFunctions);
    sortAndUnique(builder_.rawTestFunctions);
    sortAndUnique(builder_.rawInitFunctions);
    sortAndUnique(builder_.rawPreMainFunctions);
    sortAndUnique(builder_.rawDropFunctions);
    sortAndUnique(builder_.rawMainFunctions);
    sortAndUnique(builder_.regularGlobals);

    for (SymbolFunction* symbol : builder_.rawFunctions)
    {
        compiler.addNativeCodeFunction(symbol);

        NativeFunctionInfo info;
        info.symbol      = symbol;
        info.machineCode = &symbol->loweredCode();
        info.sortKey     = makeSymbolSortKey(*symbol);
        info.symbolName  = std::format("__swc_fn_{:06}_{:08x}", builder_.functionInfos.size(), Math::hash(info.sortKey));
        info.debugName   = symbol->getFullScopedName(builder_.ctx());
        info.exported    = symbol->isPublic() && !isCompilerFunction(*symbol);
        info.compilerFn  = isCompilerFunction(*symbol);
        builder_.functionInfos.push_back(std::move(info));
    }

    for (const auto& info : builder_.functionInfos)
        builder_.functionBySymbol.emplace(info.symbol, &info);

    for (SymbolFunction* symbol : builder_.rawTestFunctions)
        compiler.addNativeTestFunction(symbol);
    for (SymbolFunction* symbol : builder_.rawInitFunctions)
        compiler.addNativeInitFunction(symbol);
    for (SymbolFunction* symbol : builder_.rawPreMainFunctions)
        compiler.addNativePreMainFunction(symbol);
    for (SymbolFunction* symbol : builder_.rawDropFunctions)
        compiler.addNativeDropFunction(symbol);
    for (SymbolFunction* symbol : builder_.rawMainFunctions)
        compiler.addNativeMainFunction(symbol);

    return Result::Continue;
}

void NativeSymbolCollector::collectCompilerEntryFunctions()
{
    std::vector<SymbolFunction*> compilerEntryFunctions;
    builder_.compiler().appendCompilerEntryFunctions(compilerEntryFunctions);
    for (SymbolFunction* symbol : compilerEntryFunctions)
    {
        if (!symbol)
            continue;

        collectFunction(*symbol);
    }
}

void NativeSymbolCollector::collectSymbolsRec(const SymbolMap& symbolMap)
{
    std::vector<const Symbol*> symbols;
    symbolMap.getAllSymbols(symbols);
    for (const Symbol* symbol : symbols)
    {
        SWC_ASSERT(symbol != nullptr);

        if (symbol->isFunction())
        {
            auto* function = const_cast<SymbolFunction*>(symbol->safeCast<SymbolFunction>());
            SWC_ASSERT(function != nullptr);
            collectFunction(*function);
            continue;
        }

        if (symbol->isVariable())
        {
            auto* variable = const_cast<SymbolVariable*>(symbol->safeCast<SymbolVariable>());
            SWC_ASSERT(variable != nullptr);
            if (variable->hasGlobalStorage())
                builder_.regularGlobals.push_back(variable);
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

void NativeSymbolCollector::collectGlobalVariablesRec(const SymbolMap& symbolMap)
{
    std::vector<const Symbol*> symbols;
    symbolMap.getAllSymbols(symbols);
    for (const Symbol* symbol : symbols)
    {
        SWC_ASSERT(symbol != nullptr);

        if (symbol->isVariable())
        {
            auto* variable = const_cast<SymbolVariable*>(symbol->safeCast<SymbolVariable>());
            SWC_ASSERT(variable != nullptr);
            if (variable->hasGlobalStorage())
                builder_.regularGlobals.push_back(variable);
            continue;
        }

        if (symbol->kind() == SymbolKind::Namespace)
            collectGlobalVariablesRec(*const_cast<SymbolMap*>(symbol->asSymMap()));
    }
}

void NativeSymbolCollector::collectFunction(SymbolFunction& symbol)
{
    if (symbol.isForeign() || symbol.isEmpty() || symbol.isAttribute())
        return;
    if (!symbol.isSemaCompleted())
        return;
    if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
        return;

    const CompilerFunctionKind compilerKind = classifyCompilerFunction(symbol);
    if (compilerKind == CompilerFunctionKind::Excluded)
        return;
    if (!seenFunctions_.insert(&symbol).second)
        return;

    builder_.rawFunctions.push_back(&symbol);

    switch (compilerKind)
    {
        case CompilerFunctionKind::Test:
            builder_.rawTestFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::Init:
            builder_.rawInitFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::PreMain:
            builder_.rawPreMainFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::Drop:
            builder_.rawDropFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::Main:
            builder_.rawMainFunctions.push_back(&symbol);
            break;
        case CompilerFunctionKind::None:
        case CompilerFunctionKind::Excluded:
            break;
    }
}

Result NativeSymbolCollector::scheduleCodeGen() const
{
    if (builder_.functionInfos.empty())
        return Result::Continue;

    SourceFile* firstFile = nullptr;
    for (SourceFile* const file : builder_.compiler().files())
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
    for (const auto& info : builder_.functionInfos)
    {
        SWC_ASSERT(info.symbol != nullptr);
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
        return Result::Error;

    for (const auto& info : builder_.functionInfos)
    {
        if (!info.machineCode || info.machineCode->bytes.empty())
            return builder_.reportError(DiagnosticId::cmd_err_native_codegen_machine_code_missing, Diagnostic::ARG_SYM, info.symbolName);
    }

    return Result::Continue;
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
    Utf8 key;
    if (const SourceFile* file = builder_.compiler().srcView(symbol.srcViewRef()).file())
        key += Utf8(file->path());

    key += "|";
    key += std::to_string(symbol.tokRef().get());
    key += "|";
    key += symbol.getFullScopedName(builder_.ctx());
    key += "|";
    key += symbol.computeName(builder_.ctx());
    return key;
}

Utf8 NativeSymbolCollector::makeSortKey(const SymbolFunction& symbol) const
{
    return makeSymbolSortKey(symbol);
}

Utf8 NativeSymbolCollector::makeSortKey(const SymbolVariable& symbol) const
{
    Utf8 key;
    if (const SourceFile* file = builder_.compiler().srcView(symbol.srcViewRef()).file())
        key += Utf8(file->path());
    key += "|";
    key += std::to_string(symbol.tokRef().get());
    key += "|";
    key += symbol.getFullScopedName(builder_.ctx());
    return key;
}

SWC_END_NAMESPACE();
