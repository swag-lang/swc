#include "pch.h"
#include "Compiler/ModuleApi/ModuleApi.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool samePublicEntryNamespacePath(std::span<const IdentifierRef> lhs, std::span<const IdentifierRef> rhs)
    {
        return lhs.size() == rhs.size() && std::equal(lhs.begin(), lhs.end(), rhs.begin());
    }

    ModuleApiPublicEntry* findMatchingPublicEntry(std::vector<ModuleApiPublicEntry>& entries, const ModuleApiPublicEntry& needle)
    {
        for (ModuleApiPublicEntry& entry : entries)
        {
            if (entry.rootRef == needle.rootRef && samePublicEntryNamespacePath(entry.namespacePath, needle.namespacePath))
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

    // True for an `impl Interface for Struct {}` block that has no member functions (a
    // marker interface, or one whose methods are all defaulted) and where both the struct
    // and the interface are public. Such impls are not reconstructed from member entries,
    // so they must be emitted on their own to preserve the implementation relationship.
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
    // AST-dependent classification of a candidate symbol. Must only run once sema is
    // fully done for the module: it walks whole file ASTs, which other sema jobs mutate
    // in place (node id flips, child span rewrites) while they are still running.
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

        AstNodeRef declRef;
        if (!ModuleApi::Internal::tryFindNodeRef(astFile->ast(), symbol.decl(), declRef))
        {
            if (astFile->ast().hasSourceView() && symbol.srcViewRef() != astFile->ast().srcView().ref())
                declRef = astFile->ast().tryFindNodeRef(symbol.decl());
        }
        if (declRef.isInvalid())
            return Result::Continue;
        if (!ModuleApi::Internal::isExportedPublicDeclScope(*astFile, declRef, symbol))
            return Result::Continue;

        if (symbol.isVariable())
        {
            if (ModuleApi::Internal::hasExplicitPublicAccessModifier(*astFile, declRef))
                return reportModuleApiPublicGlobalVariable(ctx, symbol);
            return Result::Continue;
        }

        ModuleApiPublicEntry publicEntry;
        publicEntry.rootRef = ModuleApi::Internal::findExportDeclRoot(*astFile, declRef);
        publicEntry.symbol  = &symbol;
        if (publicEntry.rootRef.isInvalid())
            return Result::Continue;

        if (!ModuleApi::Internal::extractPublicNamespacePath(ctx, *astFile, declRef, symbol, publicEntry.namespacePath))
            return Result::Continue;

        addPublicEntry(fileEntry, publicEntry);
        return Result::Continue;
    }
}

namespace ModuleApi
{
    void onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol)
    {
        // This callback fires while sema jobs are still mutating ASTs on other threads,
        // so it must not walk any AST. Apply the symbol-only filters here and defer the
        // AST-dependent classification to resolvePendingEntries(), which runs post-sema.
        //
        // An interface impl carries no Public flag of its own; it is exported only through
        // its public member functions. A marker / default-only interface impl has none, so
        // it would vanish from the generated module API -- losing the struct<->interface
        // relationship across the module boundary and breaking `is`/interface casts on the
        // consumer side. Resurrect such empty interface impls when both the implementing
        // struct and the interface are themselves public.
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

    Result resolvePendingEntries(TaskContext& ctx, std::unordered_map<SourceViewRef, ModuleApiFileEntry>& entries, const bool diagnosticsOnly)
    {
        std::vector<ModuleApiFileEntry*> fileEntries;
        fileEntries.reserve(entries.size());
        for (auto& [srcViewRef, entry] : entries)
        {
            if (!entry.pendingSymbols.empty())
                fileEntries.push_back(&entry);
        }

        std::vector results(fileEntries.size(), Result::Continue);
        Export::parallelForIndexed(ctx, static_cast<uint32_t>(fileEntries.size()), [&](TaskContext& workerCtx, uint32_t i) {
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
