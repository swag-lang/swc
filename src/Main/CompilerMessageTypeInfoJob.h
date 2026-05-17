#pragma once
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

class CompilerMessageTypeInfoJob : public Job
{
public:
    static constexpr auto K = JobKind::CompilerMessage;

    explicit CompilerMessageTypeInfoJob(const TaskContext& ctx);
    JobResult exec() override;

private:
    CompilerInstance::CompilerMessageTypeInfoPrepRequest currentRequest_;
    bool                                                 hasCurrentRequest_ = false;
};

SWC_END_NAMESPACE();
