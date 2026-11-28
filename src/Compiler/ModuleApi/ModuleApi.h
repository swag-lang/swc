#pragma once
#include "Compiler/ModuleApi/ModuleApi.Types.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;

namespace ModuleApi
{
    bool   isCurrentModuleSourceFile(const SourceFile& sourceFile);

    void   onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol);
    Result collectPublicEntries(TaskContext& ctx, ModuleApiFileEntries& outEntries);
}

SWC_END_NAMESPACE();
