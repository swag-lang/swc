#pragma once

SWC_BEGIN_NAMESPACE()

class TaskContext;

namespace FileSystem
{
    AstStepResult resolveFile(TaskContext& ctx, fs::path& file);
    AstStepResult resolveFolder(TaskContext& ctx, fs::path& folder);
    Utf8   normalizeSystemMessage(const Utf8& msg);
    Utf8   normalizeSystemMessage(std::error_code ec);
    void   collectSwagFilesRec(const TaskContext& ctx, const fs::path& folder, std::vector<fs::path>& files, bool canFilter = true);
}

SWC_END_NAMESPACE()
