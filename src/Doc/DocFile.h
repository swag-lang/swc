#pragma once

#include "Doc/DocTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CompilerInstance;
class TaskContext;

class DocFile
{
public:
    static Result   read(TaskContext& ctx, const fs::path& path, std::string& outText);
    static Result   reportError(TaskContext& ctx, const fs::path& path, const Utf8& because);
    static Result   write(TaskContext& ctx, const fs::path& path, std::string_view content);
    static fs::path outputPath(const CompilerInstance& compiler, const DocPageOptions& options);
};

SWC_END_NAMESPACE();
