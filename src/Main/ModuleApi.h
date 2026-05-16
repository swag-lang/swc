#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class TaskContext;

struct ModuleApiFileEntry
{
    std::vector<AstNodeRef> publicRootRefs;
};

struct ModuleApiPerThreadData
{
    std::unordered_map<SourceViewRef, ModuleApiFileEntry> files;
};

namespace ModuleApi
{
    void   onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol);
    Result exportFiles(TaskContext& ctx);
}

SWC_END_NAMESPACE();
