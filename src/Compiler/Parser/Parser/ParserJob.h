#pragma once
#include "Support/Core/Result.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;

struct ParserJobOptions
{
    bool emitTrivia                 = false;
    bool ignoreGlobalCompilerIfSkip = false;
    bool allowReservedIdentifiers   = false;
};

Result parseLoadedSourceFile(TaskContext& ctx, SourceFile& file, ParserJobOptions options);

// Parse a fixed set of independent files and wait for the set to finish. Workers
// claim file indices directly, so the scheduler owns at most one job per worker.
void parseSourceFiles(const TaskContext& ctx, std::span<SourceFile* const> files, ParserJobOptions options = {});

SWC_END_NAMESPACE();
