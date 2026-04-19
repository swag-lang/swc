#pragma once
#include "Format/FormatOptions.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;

class Formatter
{
public:
    explicit Formatter(const FormatOptions& options = {});

    void   prepare(const SourceFile& file);
    Result write(TaskContext& ctx) const;

    bool changed() const;
    bool skipped() const;

private:
    static Result reportFormatFailure(TaskContext& ctx, const SourceFile& file, const Utf8& because);

    FormatOptions     options_;
    const SourceFile* file_    = nullptr;
    Utf8              text_;
    bool              changed_ = false;
    bool              skipped_ = false;
};

SWC_END_NAMESPACE();
