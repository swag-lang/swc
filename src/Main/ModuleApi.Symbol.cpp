#include "pch.h"
#include "Main/ModuleApi.h"
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

    void recordPublicEntry(ModuleApiPerThreadData& state, const SourceViewRef srcViewRef, const ModuleApiPublicEntry& publicEntry)
    {
        if (!srcViewRef.isValid() || publicEntry.rootRef.isInvalid())
            return;

        ModuleApiFileEntry&   entry         = state.files[srcViewRef];
        ModuleApiPublicEntry* existingEntry = findMatchingPublicEntry(entry.publicEntries, publicEntry);
        if (!existingEntry)
            entry.publicEntries.push_back(publicEntry);
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

namespace ModuleApi
{
    void onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol)
    {
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

        AstNodeRef declRef;
        if (!Internal::tryFindNodeRef(astFile->ast(), symbol.decl(), declRef))
        {
            if (astFile->ast().hasSourceView() && symbol.srcViewRef() != astFile->ast().srcView().ref())
                declRef = astFile->ast().tryFindNodeRef(symbol.decl());
        }
        if (declRef.isInvalid())
            return;
        if (!Internal::isExportedPublicDeclScope(*astFile, declRef, symbol))
            return;

        if (symbol.isVariable())
        {
            if (Internal::hasExplicitPublicAccessModifier(*astFile, declRef))
                reportModuleApiPublicGlobalVariable(ctx, symbol);
            return;
        }

        ModuleApiPublicEntry publicEntry;
        publicEntry.rootRef = Internal::findExportDeclRoot(*astFile, declRef);
        publicEntry.symbol  = &symbol;
        if (publicEntry.rootRef.isInvalid())
            return;

        if (!Internal::extractPublicNamespacePath(ctx, *astFile, declRef, symbol, publicEntry.namespacePath))
            return;

        recordPublicEntry(state, symbol.srcViewRef(), publicEntry);
    }
}

SWC_END_NAMESPACE();
