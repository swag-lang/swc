#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

struct ParserJobOptions
{
    bool emitTrivia       = false;
    bool ignoreGlobalSkip = false;
};

class ParserJob : public Job
{
public:
    static constexpr auto K = JobKind::Sema;
    ParserJob(const TaskContext& ctx, SourceFile* file, ParserJobOptions options = {});

    JobResult exec() override;

private:
    SourceFile*       file_    = nullptr;
    ParserJobOptions  options_{};
};

SWC_END_NAMESPACE();
