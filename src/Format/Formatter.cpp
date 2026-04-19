#include "pch.h"
#include "Format/Formatter.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/SourceFile.h"
#include "Format/AstSourceWriter.h"
#include "Main/FileSystem.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Formatter::Formatter(const FormatOptions& options) :
    options_(options)
{
}

void Formatter::prepare(const SourceFile& file)
{
    file_ = &file;
    if (shouldSkipFormatting(file.ast()))
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

bool Formatter::shouldSkipFormatting(const Ast& ast)
{
    if (ast.root().isInvalid())
        return false;

    const AstNode& rootNode = ast.node(ast.root());
    if (!rootNode.is(AstNodeId::File))
        return false;

    const auto&             fileNode = rootNode.cast<AstFile>();
    SmallVector<AstNodeRef> globals;
    ast.appendNodes(globals, fileNode.spanGlobalsRef);

    for (const AstNodeRef globalRef : globals)
    {
        const AstNode& globalNode = ast.node(globalRef);
        if (!globalNode.is(AstNodeId::CompilerGlobal))
            continue;

        const auto& compilerGlobal = globalNode.cast<AstCompilerGlobal>();
        if (compilerGlobal.mode == AstCompilerGlobal::Mode::SkipFmt)
            return true;
    }

    return false;
}

Result Formatter::reportFormatFailure(TaskContext& ctx, const SourceFile& file, const Utf8& because)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_format_failed);
    FileSystem::setDiagnosticPathAndBecause(diag, &ctx, file.path(), because);
    diag.report(ctx);
    return Result::Error;
}

SWC_END_NAMESPACE();
