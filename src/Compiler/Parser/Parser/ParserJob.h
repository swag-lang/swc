#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class ParserJob : public Job
{
public:
    static constexpr auto K = JobKind::Sema;
    ParserJob(const TaskContext& ctx, SourceFile* file);

    JobResult   exec() override;

private:
    SourceFile* file_ = nullptr;
};

SWC_END_NAMESPACE();
