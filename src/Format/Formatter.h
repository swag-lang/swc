#pragma once
#include "Format/AstSourceWriter.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;

namespace Format
{
    struct PreparedFile
    {
        const SourceFile* file    = nullptr;
        Utf8              text;
        bool              changed = false;
        bool              skipped = false;
    };

    void   prepareFile(const SourceFile& file, const Options& options, PreparedFile& outFile);
    Result writeFile(TaskContext& ctx, const PreparedFile& preparedFile);
}

SWC_END_NAMESPACE();
