#pragma once
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;
struct ParserJobOptions;

namespace ParseCache
{
    // Only immutable compiler-owned inputs are cached. Semantic payloads are never
    // published, and every consumer receives a private syntax tree.
    fs::path path(const TaskContext& ctx, const SourceFile& file, ParserJobOptions options);
    bool     read(TaskContext& ctx, SourceFile& file, const fs::path& path);
    void     write(SourceFile& file, const fs::path& path);
}

SWC_END_NAMESPACE();
