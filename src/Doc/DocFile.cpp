#include "pch.h"
#include "Doc/DocFile.h"
#include "Doc/DocGenerator.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 defaultOutputBaseName(const CompilerInstance& compiler, const DocPageOptions& options)
    {
        if (!options.outputName.empty())
            return options.outputName;

        if (!compiler.cmdLine().workspacePath.empty() && !compiler.cmdLine().modulePath.empty())
        {
            Utf8 result = compiler.cmdLine().workspacePath.filename();
            result += ".";
            result.append(compiler.cmdLine().modulePath.filename().string());
            return result;
        }

        return defaultArtifactName(compiler.cmdLine());
    }
}

Result DocFile::read(TaskContext& ctx, const fs::path& path, std::string& outText)
{
    FileSystem::IoErrorInfo error;
    if (FileSystem::readTextFile(path, outText, error) != Result::Continue)
        return reportError(ctx, path, FileSystem::describeIoFailure(error));
    return Result::Continue;
}

Result DocFile::reportError(TaskContext& ctx, const fs::path& path, const Utf8& because)
{
    Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_doc_file_write_failed);
    FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
    diag.report(ctx);
    return Result::Error;
}

Result DocFile::write(TaskContext& ctx, const fs::path& path, const std::string_view content)
{
    if (!ctx.cmdLine().outputDoc)
        return Result::Continue;

    FileSystem::IoErrorInfo error;
    if (FileSystem::writeBinaryFile(path, content.data(), content.size(), error) != Result::Continue)
        return reportError(ctx, path, FileSystem::describeIoFailure(error));
    return Result::Continue;
}

fs::path DocFile::outputPath(const CompilerInstance& compiler, const DocPageOptions& options)
{
    Utf8 baseName = defaultOutputBaseName(compiler, options);
    baseName.make_lower();
    baseName += ".html";
    const fs::path result = DocGenerator::outputDirectory(compiler) / fs::path(baseName.c_str());
    return result.lexically_normal();
}

SWC_END_NAMESPACE();
