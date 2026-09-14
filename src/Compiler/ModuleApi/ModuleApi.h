#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Os/DirectoryLock.h"

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
    struct SourceSnapshot
    {
        fs::path           path;
        std::string        content;
        fs::file_time_type writeTime{};
    };

    // Readers keep this access until metadata and source bytes have been captured. A failed
    // or terminated publisher leaves its marker behind, so a partial API is never imported.
    class DirectoryAccess
    {
    public:
        Result openRead(Utf8& outBecause, const fs::path& directory);
        Result beginPublication(Utf8& outBecause, const fs::path& directory);
        Result completePublication(Utf8& outBecause);

    private:
        Os::DirectoryLock lock_;
        fs::path          incompletePath_;
    };

    bool   isCurrentModuleSourceFile(const SourceFile& sourceFile);
    bool   isPublishedFile(const fs::path& path);
    Result writeSnapshot(TaskContext& ctx, std::span<const SourceSnapshot> files, const fs::path& sourceDirectory, const fs::path& destinationDirectory);
    void   onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol);
    Result collectPublicEntries(TaskContext& ctx, ModuleApiFileEntries& outEntries, bool diagnosticsOnly = false);
    Result exportFiles(TaskContext& ctx);
}

SWC_END_NAMESPACE();
