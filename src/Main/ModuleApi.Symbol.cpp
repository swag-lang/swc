#include "pch.h"
#include "Main/ModuleApi.Priv.h"
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
    void recordPublicEntry(ModuleApiPerThreadData& state, const SourceViewRef srcViewRef, const ModuleApiPublicEntry& publicEntry)
    {
        if (!srcViewRef.isValid() || publicEntry.rootRef.isInvalid())
            return;

        ModuleApiFileEntry& entry = state.files[srcViewRef];
        const auto          it    = std::ranges::find_if(entry.publicEntries, [&](const ModuleApiPublicEntry& candidate) {
            return candidate.rootRef == publicEntry.rootRef &&
                   candidate.namespacePath.size() == publicEntry.namespacePath.size() &&
                   std::equal(candidate.namespacePath.begin(), candidate.namespacePath.end(), publicEntry.namespacePath.begin());
        });

        if (it == entry.publicEntries.end())
            entry.publicEntries.push_back(publicEntry);
        else if (!it->symbol)
            it->symbol = publicEntry.symbol;
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
        if (!tryFindNodeRef(sourceFile->ast(), symbol.decl(), declRef))
            return;
        if (!isExportedPublicDeclScope(*sourceFile, declRef, symbol))
            return;

        if (symbol.isVariable())
        {
            if (hasExplicitPublicAccessModifier(*sourceFile, declRef))
                reportModuleApiPublicGlobalVariable(ctx, symbol);
            return;
        }

        ModuleApiPublicEntry publicEntry;
        publicEntry.rootRef = findExportDeclRoot(*sourceFile, declRef);
        publicEntry.symbol  = &symbol;
        if (publicEntry.rootRef.isInvalid())
            return;

        if (!extractPublicNamespacePath(symbol, publicEntry.namespacePath))
            return;

        recordPublicEntry(state, symbol.srcViewRef(), publicEntry);
    }
}

SWC_END_NAMESPACE();
