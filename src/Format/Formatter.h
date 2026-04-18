#pragma once
#include "Format/AstSourceWriter.h"

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

    Result prepareFile(TaskContext& ctx, const SourceFile& file, const Options& options, PreparedFile& outFile);
    Result writeFile(TaskContext& ctx, const PreparedFile& preparedFile);
}

SWC_END_NAMESPACE();
