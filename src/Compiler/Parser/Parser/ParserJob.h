#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class ParserJob : public Job
{
public:
    static constexpr JobKind K = JobKind::Sema;
    ParserJob(const TaskContext& ctx, SourceFile* file);

private:
    SourceFile* file_ = nullptr;
    JobResult   exec();
};

SWC_END_NAMESPACE();
