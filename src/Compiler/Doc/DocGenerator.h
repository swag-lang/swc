#pragma once
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class TaskContext;

class DocGenerator
{
public:
    struct GenerateResult
    {
        fs::path primaryOutput;
        uint32_t numFiles = 0;
    };

    explicit DocGenerator(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }

    Result          generate(GenerateResult& outResult) const;
    static fs::path outputDirectory(const CompilerInstance& compiler);
    static Utf8     renderMarkdownForTest(TaskContext& ctx, std::string_view text);

private:
    TaskContext* ctx_ = nullptr;
};

SWC_END_NAMESPACE();
