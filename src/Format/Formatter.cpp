#include "pch.h"
#include "Format/Formatter.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/SourceFile.h"
#include "Format/AstSourceWriter.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Formatter::Formatter(FormatOptions options) :
    options_(std::move(options))
{
}

void Formatter::prepare(const Global& global, const SourceFile& file)
{
    prepareParsed(global, file, true);
}

void Formatter::prepareParsed(const Global& global, const SourceFile& file, const bool rewriteSyntax)
{
    file_ = &file;
    if (file.mustSkipFormat())
    {
        text_    = file.sourceView();
        changed_ = false;
        skipped_ = true;
        return;
    }

    FormatContext formatCtx = {
        .ast           = &file.ast(),
        .srcView       = file.ast().hasSourceView() ? &file.ast().srcView() : nullptr,
        .options       = &options_,
        .rewriteSyntax = rewriteSyntax,
    };

    const AstSourceWriter writer(formatCtx);
    writer.write();

    // Rewritten tokens need their own AST before they can be laid out. A
    // rewrite the parser rejects is dropped, and the file is formatted as
    // it was written.
    if (formatCtx.syntaxRewritten)
    {
        Formatter rewritten(options_);
        if (rewritten.prepareSource(global, formatCtx.output.view(), false) == Result::Continue)
            formatCtx.output = std::move(rewritten.text_);
        else
        {
            formatCtx.rewriteSyntax   = false;
            formatCtx.syntaxRewritten = false;
            writer.write();
        }
    }

    text_    = std::move(formatCtx.output);
    changed_ = text_.view() != file.sourceView();
    skipped_ = false;
}

Result Formatter::prepare(const Global& global, const std::string_view source)
{
    return prepareSource(global, source, true);
}

Result Formatter::prepareSource(const Global& global, const std::string_view source, const bool rewriteSyntax)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "formatter_inline";

    CompilerInstance compiler(global, cmdLine);
    TaskContext      ctx(compiler);
    ctx.setMuteOutput(!rewriteSyntax);

    const fs::path path       = "formatter_inline.swg";
    SourceFile&    sourceFile = compiler.addLoadedFile(path, FileFlagsE::CustomSrc, source);

    constexpr ParserJobOptions parserOptions = {
        .emitTrivia                 = true,
        .ignoreGlobalCompilerIfSkip = true,
        .allowReservedIdentifiers   = true,
    };

    SWC_RESULT(parseLoadedSourceFile(ctx, sourceFile, parserOptions));
    if (ctx.hasError())
        return Result::Error;

    prepareParsed(global, sourceFile, rewriteSyntax);
    file_ = nullptr;
    return Result::Continue;
}

Result Formatter::write(TaskContext& ctx) const
{
    if (!file_)
        return Result::Continue;
    if (!changed_)
        return Result::Continue;

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
