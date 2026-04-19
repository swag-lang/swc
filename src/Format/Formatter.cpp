#include "pch.h"
#include "Format/Formatter.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"
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

    Result reportFormatFailure(TaskContext& ctx, const SourceFile& file, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_format_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, file.path(), because);
        diag.report(ctx);
        return Result::Error;
    }
}

void prepareFormatFile(const SourceFile& file, const FormatOptions& options, FormatPreparedFile& outFile)
{
    outFile.file = &file;
    if (shouldSkipFormatting(file.ast()))
    {
        outFile.text    = file.sourceView();
        outFile.changed = false;
        outFile.skipped = true;
        return;
    }

    FormatContext formatCtx = {
        .ast     = &file.ast(),
        .srcView = file.ast().hasSourceView() ? &file.ast().srcView() : nullptr,
        .options = &options,
    };

    AstSourceWriter writer(formatCtx);
    writer.write();

    outFile.text    = std::move(formatCtx.output);
    outFile.changed = outFile.text.view() != file.sourceView();
    outFile.skipped = false;
}

Result writeFormatFile(TaskContext& ctx, const FormatPreparedFile& preparedFile)
{
    if (!preparedFile.file)
        return Result::Continue;
    if (!preparedFile.changed)
        return Result::Continue;

    FileSystem::IoErrorInfo ioError;
    if (FileSystem::writeBinaryFile(preparedFile.file->path(), preparedFile.text.data(), preparedFile.text.size(), ioError) != Result::Continue)
        return reportFormatFailure(ctx, *preparedFile.file, FileSystem::describeIoFailure(ioError));

    return Result::Continue;
}

SWC_END_NAMESPACE();
