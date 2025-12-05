#pragma once
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class ParserJob : public Job
{
    SourceFile* file_ = nullptr;

    JobResult exec();

public:
    static constexpr auto K = JobKind::Sema;

    ParserJob(const TaskContext& ctx, SourceFile* file);
};

SWC_END_NAMESPACE()
