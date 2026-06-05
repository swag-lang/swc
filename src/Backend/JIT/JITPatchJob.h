#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

class JITPatchJob : public Job
{
public:
    static constexpr auto K = JobKind::JitPatch;

    JITPatchJob(const TaskContext& ctx, SymbolFunction& symbolFunc, const SymbolFunction* weakRelocationBlocker);
    JobResult exec() override;

    static bool schedule(TaskContext& ctx, SymbolFunction& symbolFunc, const SymbolFunction* weakRelocationBlocker = nullptr);

private:
    SymbolFunction*       symbolFunc_              = nullptr;
    const SymbolFunction* weakRelocationBlocker_   = nullptr;
};

SWC_END_NAMESPACE();
