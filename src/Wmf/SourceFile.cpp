#include "pch.h"
#include "Wmf/SourceFile.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Wmf/Verify.h"

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

Ast& SourceFile::ast()
{
    return nodePayloadContext_->ast();
}

const Ast& SourceFile::ast() const
{
    return nodePayloadContext_->ast();
}

void SourceFile::setModuleNamespace(SymbolNamespace& ns) const
{
    nodePayloadContext_->setModuleNamespace(ns);
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
        auto diag = Diagnostic::get(DiagnosticId::io_err_open_file, ref());
        diag.addArgument(Diagnostic::ARG_PATH, path_.string());
        diag.addArgument(Diagnostic::ARG_BECAUSE, Os::systemError());
        diag.report(ctx);
        return Result::Error;
    }

    const auto fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    content_.reserve(static_cast<size_t>(fileSize) + TRAILING_0);
    content_.resize(fileSize);

    if (!file.read(reinterpret_cast<char*>(content_.data()), fileSize))
    {
        auto diag = Diagnostic::get(DiagnosticId::io_err_read_file, ref());
        diag.addArgument(Diagnostic::ARG_PATH, path_.string());
        diag.addArgument(Diagnostic::ARG_BECAUSE, Os::systemError());
        diag.report(ctx);
        return Result::Error;
    }

    // Ensure we have at least 4 characters in the buffer
    for (int i = 0; i < TRAILING_0; i++)
        content_.push_back(0);

    auto& srcView = ctx.compiler().addSourceView(fileRef_);
    ast().setSourceView(srcView);
    return Result::Continue;
}

SWC_END_NAMESPACE();
