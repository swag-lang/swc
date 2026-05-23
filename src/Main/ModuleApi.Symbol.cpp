#include "pch.h"
#include "Main/ModuleApi.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
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

    void recordPublicEntry(ModuleApiPerThreadData& state, const SourceViewRef srcViewRef, const ModuleApiPublicEntry& publicEntry)
    {
        if (!srcViewRef.isValid() || publicEntry.rootRef.isInvalid())
            return;

        ModuleApiFileEntry& entry = state.files[srcViewRef];
        ModuleApiPublicEntry* existingEntry = findMatchingPublicEntry(entry.publicEntries, publicEntry);
        if (!existingEntry)
            entry.publicEntries.push_back(publicEntry);
        else if (!existingEntry->symbol)
            existingEntry->symbol = publicEntry.symbol;
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

namespace ModuleApi
{
    void onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol)
    {
        if (!symbol.isPublic())
            return;

        const SourceFile* sourceFile = ctx.compiler().sourceViewFile(symbol);
        if (!sourceFile || !sourceFile->hasFlag(FileFlagsE::ModuleSrc) || sourceFile->isImportedApi())
            return;
        if (!symbol.decl())
            return;
        if (symbol.isFunction() && symbol.decl()->isNot(AstNodeId::FunctionDecl))
            return;
        if (symbol.isImpl())
            return;

        AstNodeRef declRef;
        if (!Internal::tryFindNodeRef(sourceFile->ast(), symbol.decl(), declRef))
            return;
        if (!Internal::isExportedPublicDeclScope(*sourceFile, declRef, symbol))
            return;

        if (symbol.isVariable())
        {
            if (Internal::hasExplicitPublicAccessModifier(*sourceFile, declRef))
                reportModuleApiPublicGlobalVariable(ctx, symbol);
            return;
        }

        ModuleApiPublicEntry publicEntry;
        publicEntry.rootRef = Internal::findExportDeclRoot(*sourceFile, declRef);
        publicEntry.symbol  = &symbol;
        if (publicEntry.rootRef.isInvalid())
            return;

        if (!Internal::extractPublicNamespacePath(symbol, publicEntry.namespacePath))
            return;

        recordPublicEntry(state, symbol.srcViewRef(), publicEntry);
    }
}

SWC_END_NAMESPACE();
