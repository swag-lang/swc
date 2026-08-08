#pragma once
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class TaskContext;

namespace Command
{
    Result createProject(TaskContext& ctx);
    void   dryRun(CompilerInstance& compiler);
    void   showConfig(CompilerInstance& compiler);
    void   format(CompilerInstance& compiler);
    void   syntax(CompilerInstance& compiler);
    void   sema(CompilerInstance& compiler);
    void   doc(CompilerInstance& compiler);
    void   test(CompilerInstance& compiler);
    void   build(CompilerInstance& compiler);
    void   run(CompilerInstance& compiler);
}

SWC_END_NAMESPACE();
