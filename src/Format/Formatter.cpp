#include "pch.h"
#include "Format/Formatter.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/SourceFile.h"
#include "Format/AstSourceWriter.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Formatter::Formatter(const FormatOptions& options) :
    options_(options)
{
}

void Formatter::prepare(const SourceFile& file)
{
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeFormat);
#endif
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

Result Formatter::prepare(const Global& global, const std::string_view source)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "formatter_inline";

    CompilerInstance compiler(global, cmdLine);
    TaskContext      ctx(compiler);

    const fs::path path = "formatter_inline.swg";
    compiler.registerInMemoryFile(path, source);

    SourceFile& sourceFile = compiler.addFile(path, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(ctx));

    constexpr ParserJobOptions parserOptions = {
        .emitTrivia       = true,
        .ignoreGlobalSkip = true,
    };

    SWC_RESULT(parseLoadedSourceFile(ctx, sourceFile, parserOptions));
    if (ctx.hasError())
        return Result::Error;

    prepare(sourceFile);
    file_ = nullptr;
    return Result::Continue;
}

Result Formatter::write(TaskContext& ctx) const
{
    if (!file_)
        return Result::Continue;
    if (!changed_)
        return Result::Continue;

#if SWC_HAS_STATS
    Timer time(&Stats::get().timeFormatWrite);
#endif
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
