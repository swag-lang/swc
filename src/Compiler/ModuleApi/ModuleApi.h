#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class Symbol;
class TaskContext;

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

using ModuleApiFileEntries = std::unordered_map<SourceViewRef, ModuleApiFileEntry>;

struct ModuleApiPerThreadData
{
    ModuleApiFileEntries files;
};

namespace ModuleApi
{
    bool   isCurrentModuleSourceFile(const SourceFile& sourceFile);
    void   onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol);
    Result collectPublicEntries(TaskContext& ctx, ModuleApiFileEntries& outEntries, bool diagnosticsOnly = false);
    Result exportFiles(TaskContext& ctx);
}

SWC_END_NAMESPACE();
