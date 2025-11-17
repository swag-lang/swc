#include "pch.h"
#include "Wmf/SourceFile.h"
#include "Core/Timer.h"
#include "Main/Stats.h"
#include "Os/Os.h"
#include "Parser/Ast.h"
#include "Report/Diagnostic.h"
#include "Wmf/UnitTest.h"

SWC_BEGIN_NAMESPACE()

SourceFile::~SourceFile() = default;

SourceFile::SourceFile(fs::path path) :
    path_(std::move(path))
{
    ast_      = std::make_unique<Ast>();
    unitTest_ = std::make_unique<UnitTest>(this);
}

Result SourceFile::loadContent(const TaskContext& ctx)
{
    if (!content_.empty())
        return Result::Success;

#if SWC_HAS_STATS
    Timer time(&Stats::get().timeLoadFile);
#endif

#if SWC_HAS_STATS
    Stats::get().numFiles.fetch_add(1);
#endif

    std::ifstream file(path_, std::ios::binary | std::ios::ate);

    if (!file)
    {
        auto diag = Diagnostic::get(DiagnosticId::io_err_open_file, this);
        diag.addArgument(Diagnostic::ARG_PATH, path_.string());
        diag.addArgument(Diagnostic::ARG_BECAUSE, Os::systemError());
        diag.last().setLexerOutput(&ast_->lexOut());
        diag.report(ctx);
        return Result::Error;
    }

    const auto fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    content_.reserve(static_cast<size_t>(fileSize) + TRAILING_0);
    content_.resize(fileSize);

    if (!file.read(reinterpret_cast<char*>(content_.data()), fileSize))
    {
        auto diag = Diagnostic::get(DiagnosticId::io_err_read_file, this);
        diag.addArgument(Diagnostic::ARG_PATH, path_.string());
        diag.addArgument(Diagnostic::ARG_BECAUSE, Os::systemError());
        diag.last().setLexerOutput(&ast_->lexOut());
        diag.report(ctx);
        return Result::Error;
    }

    // Ensure we have at least 4 characters in the buffer
    for (int i = 0; i < TRAILING_0; i++)
        content_.push_back(0);

    ast_->lexOut().setFile(this);
    return Result::Success;
}

SWC_END_NAMESPACE()
