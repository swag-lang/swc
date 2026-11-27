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
    // Include the relationship when both participating types are public.
    bool isDocumentedEmptyInterfaceImpl(const Symbol& symbol)
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

    // Run only after semantic analysis: classification walks complete ASTs,
    // which semantic workers can mutate in place.
    void resolvePendingSymbol(TaskContext& ctx, const Symbol& symbol, ModuleApiFileEntry& fileEntry)
    {
        const SourceFile* sourceFile = ctx.compiler().sourceViewFile(symbol);
        const SourceFile* astFile    = ctx.compiler().ownerSourceFile(symbol.srcViewRef());
        if (!astFile)
            astFile = sourceFile;

        if (!sourceFile || !astFile)
            return;

        const AstNodeRef declRef = ModuleApi::findSymbolDeclRef(astFile->ast(), symbol);
        if (declRef.isInvalid())
            return;

        if (!ModuleApi::isDocumentableDeclScope(*astFile, declRef, symbol))
            return;

        ModuleApiPublicEntry publicEntry;
        publicEntry.rootRef = ModuleApi::findDocumentedDeclRoot(*astFile, declRef);
        publicEntry.symbol  = &symbol;
        if (publicEntry.rootRef.isInvalid())
            return;

        if (!ModuleApi::extractPublicNamespacePath(ctx, *astFile, declRef, symbol, publicEntry.namespacePath))
            return;

        addPublicEntry(fileEntry, publicEntry);
    }

    void resolvePendingEntries(TaskContext& ctx, ModuleApiFileEntries& entries)
    {
        std::vector<ModuleApiFileEntry*> fileEntries;
        fileEntries.reserve(entries.size());

        for (auto& entry : entries | std::views::values)
        {
            if (!entry.pendingSymbols.empty())
                fileEntries.push_back(&entry);
        }

        JobManager& jobMgr = ctx.global().jobMgr();

        jobMgr.parallelForIndexed(
            ctx,
            static_cast<uint32_t>(fileEntries.size()),
            JobKind::DocSymbols,
            ctx.compiler().jobClientId(),
            [&](TaskContext& workerCtx, uint32_t i) {
                ModuleApiFileEntry& fileEntry = *fileEntries[i];

                for (const Symbol* symbol : fileEntry.pendingSymbols)
                    resolvePendingSymbol(workerCtx, *symbol, fileEntry);
            });
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
        // when both types are public.
        if (symbol.isVariable())
            return;

        const bool isEmptyPublicInterfaceImpl = isDocumentedEmptyInterfaceImpl(symbol);
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

    Result collectPublicEntries(TaskContext& ctx, ModuleApiFileEntries& outEntries)
    {
        outEntries.clear();

        const CompilerInstance& compiler = ctx.compiler();
        for (size_t i = 0; i < compiler.numPerThreadData(); ++i)
            mergeThreadData(outEntries, compiler.moduleApiPerThreadData(i));

        resolvePendingEntries(ctx, outEntries);
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
