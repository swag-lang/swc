#include "pch.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Verify.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

SourceFile::SourceFile(FileRef fileRef, fs::path path, FileFlags flags) :
    fileRef_(fileRef),
    path_(std::move(path)),
    flags_(flags)
{
    nodePayloadContext_ = std::make_unique<NodePayload>();
    unitTest_           = std::make_unique<Verify>(this);
}

SourceFile::~SourceFile() = default;

void SourceFile::setModuleNamespace(SymbolNamespace& ns) const
{
    nodePayloadContext_->setModuleNamespace(ns);
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

void SourceFile::addErrorLineRange(const uint32_t lineStart, const uint32_t lineEnd) const
{
    if (!lineStart || !lineEnd)
        return;

    const uint32_t firstLine = std::min(lineStart, lineEnd);
    const uint32_t lastLine  = std::max(lineStart, lineEnd);

    const std::scoped_lock lock(errorLinesMutex_);
    for (uint32_t line = firstLine; line <= lastLine; line++)
    {
        if (std::ranges::find(errorLines_, line) == errorLines_.end())
            errorLines_.push_back(line);
    }
}

bool SourceFile::hasErrorLineInRange(const uint32_t lineStart, const uint32_t lineEnd) const
{
    if (!lineStart || !lineEnd)
        return false;

    const uint32_t firstLine = std::min(lineStart, lineEnd);
    const uint32_t lastLine  = std::max(lineStart, lineEnd);

    const std::scoped_lock lock(errorLinesMutex_);
    for (const uint32_t line : errorLines_)
    {
        if (line >= firstLine && line <= lastLine)
            return true;
    }

    return false;
}

Result SourceFile::loadContent(TaskContext& ctx)
{
    if (!content_.empty())
        return Result::Continue;

#if SWC_HAS_STATS
    Timer time(&Stats::get().timeLoadFile);
#endif

#if SWC_HAS_STATS
    Stats::get().numFiles.fetch_add(1);
#endif

    std::ifstream file(path_, std::ios::binary | std::ios::ate);

    if (!file)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::io_err_open_file, ref());
        diag.addArgument(Diagnostic::ARG_PATH, path_.string());
        diag.addArgument(Diagnostic::ARG_BECAUSE, Os::systemError());
        diag.report(ctx);
        return Result::Error;
    }

    const std::streampos fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    content_.reserve(static_cast<size_t>(fileSize) + TRAILING_0);
    content_.resize(fileSize);

    if (!file.read(reinterpret_cast<char*>(content_.data()), fileSize))
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::io_err_read_file, ref());
        diag.addArgument(Diagnostic::ARG_PATH, path_.string());
        diag.addArgument(Diagnostic::ARG_BECAUSE, Os::systemError());
        diag.report(ctx);
        return Result::Error;
    }

    // Ensure we have at least 4 characters in the buffer
    for (int i = 0; i < TRAILING_0; i++)
        content_.push_back(0);

    SourceView& srcView = ctx.compiler().addSourceView(fileRef_);
    ast().setSourceView(srcView);
    return Result::Continue;
}

SWC_END_NAMESPACE();
