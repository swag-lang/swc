#pragma once
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Format/FormatOptions.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;

class FormatJob final : public Job
{
public:
    FormatJob(const TaskContext& ctx, SourceFile* file, const FormatOptions& formatOptions, ParserJobOptions parserOptions);

    JobResult exec() override;

    bool rewritten() const { return rewritten_; }
    bool skippedFmt() const { return skippedFmt_; }
    bool skippedInvalid() const { return skippedInvalid_; }

private:
    SourceFile*      file_ = nullptr;
    FormatOptions    formatOptions_{};
    ParserJobOptions parserOptions_{};
    bool             rewritten_      = false;
    bool             skippedFmt_     = false;
    bool             skippedInvalid_ = false;
};

SWC_END_NAMESPACE();
