#include "pch.h"
#include "Format/Formatter.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/SourceFile.h"
#include "Format/AstSourceWriter.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Formatter::Formatter(const FormatOptions& options) :
    options_(options)
{
}

void Formatter::prepare(const SourceFile& file)
{
    Timer time(&Stats::get().timeFormat);
    file_ = &file;
    if (file.mustSkipFormat())
    {
        text_    = file.sourceView();
        changed_ = false;
        skipped_ = true;
        return;
    }

    FormatContext formatCtx = {
        .ast     = &file.ast(),
        .srcView = file.ast().hasSourceView() ? &file.ast().srcView() : nullptr,
        .options = &options_,
    };

    AstSourceWriter writer(formatCtx);
    writer.write();

    text_    = std::move(formatCtx.output);
    changed_ = text_.view() != file.sourceView();
    skipped_ = false;
}

Result Formatter::write(TaskContext& ctx) const
{
    if (!file_)
        return Result::Continue;
    if (!changed_)
        return Result::Continue;

    Timer time(&Stats::get().timeFormatWrite);
    FileSystem::IoErrorInfo ioError;
    if (FileSystem::writeBinaryFile(file_->path(), text_.data(), text_.size(), ioError) != Result::Continue)
        return reportFormatFailure(ctx, *file_, FileSystem::describeIoFailure(ioError));

    return Result::Continue;
}

bool Formatter::changed() const
{
    return changed_;
}

bool Formatter::skipped() const
{
    return skipped_;
}

Result Formatter::reportFormatFailure(TaskContext& ctx, const SourceFile& file, const Utf8& because)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_format_failed);
    FileSystem::setDiagnosticPathAndBecause(diag, &ctx, file.path(), because);
    diag.report(ctx);
    return Result::Error;
}

SWC_END_NAMESPACE();
