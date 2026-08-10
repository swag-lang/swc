#pragma once
#include "Format/FormatOptions.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

class FormatOptionsLoader
{
public:
    FormatOptionsLoader(TaskContext& ctx, FormatNamedStyle baseStyle);
    Result resolve(const fs::path& sourcePath, FormatOptions& outOptions);
    Result resolveDirectory(const fs::path& directory, FormatOptions& outOptions);

    // Render an option set as a `.swc-format` file: every option, its documented
    // meaning, and its accepted values. The output is meant to be redirected
    // into a configuration file and edited from there.
    static Utf8 describe(const FormatOptions& options);

private:
    TaskContext*                      ctx_ = nullptr;
    FormatNamedStyle                  baseStyle_;
    std::map<fs::path, FormatOptions> cache_;

    Result applyConfigFile(FormatOptions& options, const fs::path& configPath) const;
};

SWC_END_NAMESPACE();
