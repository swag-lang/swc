#pragma once
#include "Compiler/ModuleApi/ModuleApi.Types.h"
#include "Support/Core/Result.h"
#include "Support/Os/DirectoryLock.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;

namespace ModuleApi
{
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
