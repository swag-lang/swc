#include "pch.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    size_t filePathDisplayModeIndex(const FileSystem::FilePathDisplayMode mode)
    {
        switch (mode)
        {
            case FileSystem::FilePathDisplayMode::AsIs:
                return 0;

            case FileSystem::FilePathDisplayMode::BaseName:
                return 1;

            case FileSystem::FilePathDisplayMode::Absolute:
                return 2;

            default:
                SWC_UNREACHABLE();
        }
    }

    FileSystem::FilePathDisplayMode filePathDisplayMode(const TaskContext* ctx)
    {
        if (!ctx)
            return FileSystem::FilePathDisplayMode::AsIs;
        return ctx->cmdLine().filePathDisplay;
    }
}

SourceFile::SourceFile(FileRef fileRef, fs::path path, FileFlags flags) :
    fileRef_(fileRef),
    path_(std::move(path)),
    flags_(flags)
{
    formattedFileNames_[filePathDisplayModeIndex(FileSystem::FilePathDisplayMode::AsIs)]     = path_.string();
    formattedFileNames_[filePathDisplayModeIndex(FileSystem::FilePathDisplayMode::BaseName)] = path_.filename().string();
    formattedFileNames_[filePathDisplayModeIndex(FileSystem::FilePathDisplayMode::Absolute)] = FileSystem::normalizePath(path_).string();

    nodePayloadContext_ = std::make_unique<NodePayload>();
    unitTest_           = std::make_unique<Verify>(this);
}

SourceFile::~SourceFile() = default;

const Utf8& SourceFile::formattedFileName(const TaskContext* ctx) const
{
    return formattedFileNames_[filePathDisplayModeIndex(filePathDisplayMode(ctx))];
}

Utf8 SourceFile::formatFileLocation(const TaskContext* ctx, const uint32_t line, const uint32_t column, const uint32_t columnEnd) const
{
    return FileSystem::formatFileLocation(formattedFileName(ctx), line, column, columnEnd);
}

void SourceFile::setModuleNamespace(SymbolNamespace& ns) const
{
    nodePayloadContext_->setModuleNamespace(ns);
}

const SymbolNamespace* SourceFile::moduleNamespace() const
{
    return nodePayloadContext_->moduleNamespace_;
}

void SourceFile::setFileNamespace(SymbolNamespace& ns) const
{
    nodePayloadContext_->setFileNamespace(ns);
}

const SymbolNamespace* SourceFile::fileNamespace() const
{
    return nodePayloadContext_->fileNamespace_;
}

Ast& SourceFile::ast()
{
    return nodePayloadContext_->ast();
}

const Ast& SourceFile::ast() const
{
    return nodePayloadContext_->ast();
}

void SourceFile::setContent(const std::string_view content)
{
    SWC_ASSERT(!ast().hasSourceView());

    content_.clear();
    content_.reserve(content.size() + TRAILING_0);
    content_.resize(content.size());
    if (!content.empty())
    {
        std::memcpy(content_.data(), content.data(), content.size());
    }

    for (int i = 0; i < TRAILING_0; i++)
        content_.push_back(0);
}

void SourceFile::addErrorLineRange(const uint32_t lineStart, const uint32_t lineEnd) const
{
    if (!lineStart || !lineEnd)
        return;

    const std::pair range = {
        std::min(lineStart, lineEnd),
        std::max(lineStart, lineEnd),
    };
    const std::scoped_lock lock(errorLinesMutex_);
    if (std::ranges::find(errorLineRanges_, range) == errorLineRanges_.end())
        errorLineRanges_.push_back(range);
}

bool SourceFile::hasErrorLineInRange(const uint32_t lineStart, const uint32_t lineEnd) const
{
    if (!lineStart || !lineEnd)
        return false;

    const uint32_t firstLine = std::min(lineStart, lineEnd);
    const uint32_t lastLine  = std::max(lineStart, lineEnd);

    const std::scoped_lock lock(errorLinesMutex_);
    for (const auto [errorStart, errorEnd] : errorLineRanges_)
    {
        if (errorEnd >= firstLine && errorStart <= lastLine)
            return true;
    }

    return false;
}

void SourceFile::ensureSourceView(TaskContext& ctx)
{
    if (ast().hasSourceView())
        return;

    SourceView& srcView = ctx.compiler().addSourceView(fileRef_);
    ast().setSourceView(srcView);
}

Result SourceFile::loadContent(TaskContext& ctx)
{
    if (!content_.empty())
    {
        ensureSourceView(ctx);
        return Result::Continue;
    }

    SWC_MEM_SCOPE("Frontend/LoadFile");
    Stats::get().numFiles.fetch_add(1);
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeLoadFile);
#endif

    FileSystem::IoErrorInfo ioError;
    if (FileSystem::readBinaryFile(path_, content_, ioError) != Result::Continue)
    {
        const DiagnosticId diagId = ioError.problem == FileSystem::IoProblem::OpenRead ? DiagnosticId::io_err_open_file : DiagnosticId::io_err_read_file;
        Diagnostic         diag   = Diagnostic::get(diagId, ref());
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path_, ioError.because);
        diag.report(ctx);
        return Result::Error;
    }

    // Ensure we have at least 4 characters in the buffer
    for (int i = 0; i < TRAILING_0; i++)
        content_.push_back(0);

    ensureSourceView(ctx);
    return Result::Continue;
}

SWC_END_NAMESPACE();
