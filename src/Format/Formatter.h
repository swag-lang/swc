#pragma once
#include "Format/AstSourceWriter.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;

struct FormatPreparedFile
{
    const SourceFile* file = nullptr;
    Utf8              text;
    bool              changed = false;
    bool              skipped = false;
};

void   prepareFormatFile(const SourceFile& file, const FormatOptions& options, FormatPreparedFile& outFile);
Result writeFormatFile(TaskContext& ctx, const FormatPreparedFile& preparedFile);

SWC_END_NAMESPACE();
