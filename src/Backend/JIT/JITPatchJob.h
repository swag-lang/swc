#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

class JITPatchJob : public Job
{
public:
    static constexpr auto K = JobKind::JitPatch;

    JITPatchJob(const TaskContext& ctx, SymbolFunction& symbolFunc);
    JobResult exec() override;

    static bool schedule(TaskContext& ctx, SymbolFunction& symbolFunc);

private:
    SymbolFunction* symbolFunc_ = nullptr;
};

SWC_END_NAMESPACE();
