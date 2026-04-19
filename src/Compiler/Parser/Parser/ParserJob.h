#pragma once
#include "Support/Core/Result.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;

struct ParserJobOptions
{
    bool emitTrivia       = false;
    bool ignoreGlobalSkip = false;
};

Result parseLoadedSourceFile(TaskContext& ctx, SourceFile& file, ParserJobOptions options);

class ParserJob : public Job
{
public:
    static constexpr auto K = JobKind::Parser;
    ParserJob(const TaskContext& ctx, SourceFile* file, ParserJobOptions options = {});

    JobResult exec() override;

private:
    SourceFile*       file_    = nullptr;
    ParserJobOptions  options_{};
};

SWC_END_NAMESPACE();
