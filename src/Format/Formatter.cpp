#include "pch.h"
#include "Format/Formatter.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool shouldSkipFormatting(const Ast& ast)
    {
        if (ast.root().isInvalid())
            return false;

        const AstNode& rootNode = ast.node(ast.root());
        if (!rootNode.is(AstNodeId::File))
            return false;

        const auto& fileNode = rootNode.cast<AstFile>();
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

    Result reportFormatFailure(TaskContext& ctx, const SourceFile& file, const std::string_view because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_format_failed);
        diag.addArgument(Diagnostic::ARG_PATH, FileSystem::formatFileName(&ctx, file.path()));
        diag.addArgument(Diagnostic::ARG_BECAUSE, Utf8(because));
        diag.report(ctx);
        return Result::Error;
    }
}

void Format::prepareFile(const SourceFile& file, const Options& options, PreparedFile& outFile)
{
    outFile.file = &file;
    if (shouldSkipFormatting(file.ast()))
    {
        outFile.text    = file.sourceView();
        outFile.changed = false;
        outFile.skipped = true;
        return;
    }

    Context formatCtx = {
        .ast     = &file.ast(),
        .srcView = file.ast().hasSourceView() ? &file.ast().srcView() : nullptr,
        .options = &options,
    };

    AstSourceWriter::write(formatCtx);

    outFile.text    = std::move(formatCtx.output);
    outFile.changed = outFile.text.view() != file.sourceView();
    outFile.skipped = false;
}

Result Format::writeFile(TaskContext& ctx, const PreparedFile& preparedFile)
{
    if (!preparedFile.file)
        return Result::Continue;
    if (!preparedFile.changed)
        return Result::Continue;

    std::ofstream stream(preparedFile.file->path(), std::ios::binary | std::ios::trunc);
    if (!stream.is_open())
        return reportFormatFailure(ctx, *preparedFile.file, std::format("cannot open file for writing: {}", FileSystem::normalizeSystemMessage(Os::systemError())));

    stream.write(preparedFile.text.data(), static_cast<std::streamsize>(preparedFile.text.size()));
    if (!stream)
        return reportFormatFailure(ctx, *preparedFile.file, "failed to write formatted source");

    return Result::Continue;
}

SWC_END_NAMESPACE();
