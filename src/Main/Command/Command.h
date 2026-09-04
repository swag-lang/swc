#pragma once
#include "Support/Core/Result.h"
#include <vector>

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class FormatJob;
class TaskContext;

namespace Command
{
    Result createProject(TaskContext& ctx);
    Result clean(TaskContext& ctx);
    void   dryRun(CompilerInstance& compiler);
    void   showConfig(CompilerInstance& compiler);
    void   format(CompilerInstance& compiler);

    // Selects and enqueues one FormatJob per input the `format` command would process: implicit
    // runtime inputs and generated caches are excluded. The dry-run preview shares this selection
    // so its plan cannot drift from what the real command does.
    Result enqueueFormatJobs(TaskContext& ctx, const CompilerInstance& compiler, std::vector<FormatJob*>& outJobs);
    void   syntax(CompilerInstance& compiler);
    void   sema(CompilerInstance& compiler);
    void   doc(CompilerInstance& compiler);
    void   test(CompilerInstance& compiler);
    void   build(CompilerInstance& compiler);
    void   run(CompilerInstance& compiler);
}

SWC_END_NAMESPACE();
