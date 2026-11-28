#include "pch.h"
#include "Compiler/ModuleApi/ModuleApi.h"
#include "Compiler/ModuleApi/ModuleApi.Internal.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    ModuleApiPublicEntry* findMatchingPublicEntry(std::vector<ModuleApiPublicEntry>& entries, const ModuleApiPublicEntry& needle)
    {
        for (ModuleApiPublicEntry& entry : entries)
        {
            if (entry.rootRef == needle.rootRef && ModuleApi::sameNamespacePath(entry.namespacePath, needle.namespacePath))
                return &entry;
        }

        return nullptr;
    }

    void addPublicEntry(ModuleApiFileEntry& fileEntry, const ModuleApiPublicEntry& publicEntry)
    {
        if (publicEntry.rootRef.isInvalid())
            return;

        ModuleApiPublicEntry* existingEntry = findMatchingPublicEntry(fileEntry.publicEntries, publicEntry);
        if (!existingEntry)
            fileEntry.publicEntries.push_back(publicEntry);
        else if (!existingEntry->symbol)
            existingEntry->symbol = publicEntry.symbol;
    }

    void mergeFileEntry(ModuleApiFileEntry& outEntry, const ModuleApiFileEntry& threadEntry)
    {
        // A symbol completes sema exactly once, so per-thread pending lists are disjoint.
        outEntry.pendingSymbols.insert(outEntry.pendingSymbols.end(), threadEntry.pendingSymbols.begin(), threadEntry.pendingSymbols.end());

        for (const ModuleApiPublicEntry& publicEntry : threadEntry.publicEntries)
        {
            if (!findMatchingPublicEntry(outEntry.publicEntries, publicEntry))
                outEntry.publicEntries.push_back(publicEntry);
        }
    }

    void mergeThreadData(ModuleApiFileEntries& outEntries, const ModuleApiPerThreadData& threadData)
    {
        for (const auto& [srcViewRef, threadEntry] : threadData.files)
            mergeFileEntry(outEntries[srcViewRef], threadEntry);
    }

    // Empty interface impls cannot be reconstructed from member entries.
    // Export the relationship separately when both participating types are public.
    bool isEmptyExportableInterfaceImpl(const Symbol& symbol)
    {
        if (!symbol.isImpl())
            return false;

        const auto* symImpl = symbol.safeCast<SymbolImpl>();
        if (!symImpl || !symImpl->isForInterface() || !symImpl->empty())
            return false;

        const SymbolStruct*    implStruct    = symImpl->symStruct();
        const SymbolInterface* implInterface = symImpl->symInterface();
        if (!implStruct || !implInterface)
            return false;

        return implStruct->isPublic() && implInterface->isPublic();
    }

    Result reportModuleApiPublicGlobalVariable(TaskContext& ctx, const Symbol& symbol)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_public_global_variable, ctx.compiler().srcView(symbol.srcViewRef()).fileRef());
        diag.last().addSpan(symbol.codeRange(ctx), "", DiagnosticSeverity::Error);
        diag.addArgument(Diagnostic::ARG_SYM, symbol.name(ctx));
        diag.report(ctx);

        return Result::Error;
    }
}

namespace
{
    // Run only after semantic analysis: classification walks complete ASTs,
    // which semantic workers can mutate in place.
    Result resolvePendingSymbol(TaskContext& ctx, const Symbol& symbol, ModuleApiFileEntry& fileEntry, const bool diagnosticsOnly)
    {
        if (diagnosticsOnly && !symbol.isVariable())
            return Result::Continue;

        const SourceFile* sourceFile = ctx.compiler().sourceViewFile(symbol);
        const SourceFile* astFile    = ctx.compiler().ownerSourceFile(symbol.srcViewRef());
        if (!astFile)
            astFile = sourceFile;

        if (!sourceFile || !astFile)
            return Result::Continue;

        const AstNodeRef declRef = ModuleApi::findSymbolDeclRef(astFile->ast(), symbol);
        if (declRef.isInvalid())
            return Result::Continue;

        if (!ModuleApi::isExportedPublicDeclScope(*astFile, declRef, symbol))
            return Result::Continue;

        if (symbol.isVariable())
        {
            if (ModuleApi::hasExplicitPublicAccessModifier(*astFile, declRef))
                return reportModuleApiPublicGlobalVariable(ctx, symbol);

            return Result::Continue;
        }

        ModuleApiPublicEntry publicEntry;
        publicEntry.rootRef = ModuleApi::findExportDeclRoot(*astFile, declRef);
        publicEntry.symbol  = &symbol;
        if (publicEntry.rootRef.isInvalid())
            return Result::Continue;

        if (!ModuleApi::extractPublicNamespacePath(ctx, *astFile, declRef, symbol, publicEntry.namespacePath))
            return Result::Continue;

        addPublicEntry(fileEntry, publicEntry);
        return Result::Continue;
    }
}

namespace ModuleApi
{
    void onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol)
    {
        // Other semantic workers still mutate ASTs here. Filter symbols only and defer
        // AST traversal to resolvePendingEntries after semantic analysis completes.
        //
        // Empty interface impls have no public members to register them. Include them
        // when both types are public, preserving interface casts and is tests in importers.
        const bool isEmptyPublicInterfaceImpl = isEmptyExportableInterfaceImpl(symbol);
        if (!symbol.isPublic() && !isEmptyPublicInterfaceImpl)
            return;

        const SourceFile* sourceFile = ctx.compiler().sourceViewFile(symbol);
        const SourceFile* astFile    = ctx.compiler().ownerSourceFile(symbol.srcViewRef());
        if (!astFile)
            astFile = sourceFile;

        if (!sourceFile || !astFile)
            return;
        if (!isCurrentModuleSourceFile(*sourceFile) && !isCurrentModuleSourceFile(*astFile))
            return;

        if (!symbol.decl())
            return;

        if (symbol.isFunction() && symbol.decl()->isNot(AstNodeId::FunctionDecl) && symbol.decl()->isNot(AstNodeId::AttrDecl))
            return;
        if (symbol.isFunction() && symbol.attributes().hasRtFlag(RtAttributeFlagsE::PlaceHolder))
            return;

        if (symbol.isImpl() && !isEmptyPublicInterfaceImpl)
            return;

        if (!symbol.srcViewRef().isValid())
            return;

        state.files[symbol.srcViewRef()].pendingSymbols.push_back(&symbol);
    }

    Result collectPublicEntries(TaskContext& ctx, ModuleApiFileEntries& outEntries, const bool diagnosticsOnly)
    {
        outEntries.clear();

        const CompilerInstance& compiler = ctx.compiler();
        for (size_t i = 0; i < compiler.numPerThreadData(); ++i)
            mergeThreadData(outEntries, compiler.moduleApiPerThreadData(i));

        return resolvePendingEntries(ctx, outEntries, diagnosticsOnly);
    }

    Result resolvePendingEntries(TaskContext& ctx, ModuleApiFileEntries& entries, const bool diagnosticsOnly)
    {
        std::vector<ModuleApiFileEntry*> fileEntries;
        fileEntries.reserve(entries.size());

        for (auto& entry : entries | std::views::values)
        {
            if (!entry.pendingSymbols.empty())
                fileEntries.push_back(&entry);
        }

        std::vector results(fileEntries.size(), Result::Continue);
        JobManager& jobMgr = ctx.global().jobMgr();

        jobMgr.parallelForIndexed(
            ctx,
            static_cast<uint32_t>(fileEntries.size()),
            JobKind::ModuleApiExport,
            ctx.compiler().jobClientId(),
            [&](TaskContext& workerCtx, uint32_t i) {
                ModuleApiFileEntry& fileEntry = *fileEntries[i];

                for (const Symbol* symbol : fileEntry.pendingSymbols)
                {
                    if (resolvePendingSymbol(workerCtx, *symbol, fileEntry, diagnosticsOnly) == Result::Error)
                        results[i] = Result::Error;
                }
            });

        for (const Result r : results)
        {
            if (r != Result::Continue)
                return Result::Error;
        }

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
