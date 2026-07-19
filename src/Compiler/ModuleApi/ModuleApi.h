#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Ast;
class SourceFile;
class Symbol;
class TaskContext;
struct AstNode;

struct ModuleApiPublicEntry
{
    AstNodeRef                 rootRef = AstNodeRef::invalid();
    const Symbol*              symbol  = nullptr;
    std::vector<IdentifierRef> namespacePath;
};

struct ModuleApiFileEntry
{
    // Candidate public symbols recorded while sema is still running. AST-dependent
    // classification is deferred to resolvePendingEntries(), which runs post-sema:
    // walking a file's AST while other sema jobs mutate it is a data race.
    std::vector<const Symbol*> pendingSymbols;

    // Resolved entries, produced from pendingSymbols by resolvePendingEntries().
    std::vector<ModuleApiPublicEntry> publicEntries;
};

struct ModuleApiPerThreadData
{
    std::unordered_map<SourceViewRef, ModuleApiFileEntry> files;
};

namespace ModuleApi
{
    bool   isCurrentModuleSourceFile(const SourceFile& sourceFile);
    void   onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol);
    Result resolvePendingEntries(TaskContext& ctx, std::unordered_map<SourceViewRef, ModuleApiFileEntry>& entries, bool diagnosticsOnly);
    Result exportFiles(TaskContext& ctx);

    namespace Internal
    {
        bool       tryFindNodeRef(const Ast& ast, const AstNode* targetNode, AstNodeRef& outNodeRef);
        AstNodeRef findExportDeclRoot(const SourceFile& file, AstNodeRef declRef);
        bool       hasExplicitPublicAccessModifier(const SourceFile& file, AstNodeRef declRef);
        bool       isExportedPublicDeclScope(const SourceFile& file, AstNodeRef declRef, const Symbol& symbol);
        bool       extractPublicNamespacePath(TaskContext& ctx, const SourceFile& file, AstNodeRef declRef, const Symbol& symbol, std::vector<IdentifierRef>& outNamespacePath);
    }
}

SWC_END_NAMESPACE();
