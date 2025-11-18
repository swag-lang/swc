#pragma once
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class ParserJob : public Job
{
    JobContext* ctx_  = nullptr;
    SourceFile* file_ = nullptr;

    JobResult exec(JobContext& ctx) const;

public:
    ParserJob(const TaskContext& ctx, SourceFile* file);
};

SWC_END_NAMESPACE()
