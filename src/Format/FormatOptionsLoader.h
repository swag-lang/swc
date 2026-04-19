#pragma once
#include "Format/FormatOptions.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

class FormatOptionsLoader
{
public:
    explicit FormatOptionsLoader(TaskContext& ctx);
    Result resolve(const fs::path& sourcePath, FormatOptions& outOptions);

private:
    TaskContext*                      ctx_ = nullptr;
    std::map<fs::path, FormatOptions> cache_;

    Result resolveDirectory(const fs::path& directory, FormatOptions& outOptions);
    Result applyConfigFile(FormatOptions& options, const fs::path& configPath) const;
};

SWC_END_NAMESPACE();
