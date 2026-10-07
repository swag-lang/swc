#pragma once
#include "Format/FormatOptions.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Global;
class SourceFile;
class TaskContext;

class Formatter
{
public:
    explicit Formatter(FormatOptions options = {});

    void   prepare(const Global& global, const SourceFile& file);
    Result prepare(const Global& global, std::string_view source);
    Result write(TaskContext& ctx) const;

    bool             changed() const;
    bool             skipped() const;
    std::string_view text() const { return text_.view(); }

private:
    void          prepareParsed(const Global& global, const SourceFile& file, bool rewriteSyntax);
    Result        prepareSource(const Global& global, std::string_view source, bool rewriteSyntax);
    static Result reportFormatFailure(TaskContext& ctx, const SourceFile& file, const Utf8& because);

    FormatOptions     options_;
    const SourceFile* file_ = nullptr;
    Utf8              text_;
    bool              changed_ = false;
    bool              skipped_ = false;
};

SWC_END_NAMESPACE();
