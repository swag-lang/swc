#pragma once
SWC_BEGIN_NAMESPACE()

class TaskContext;

namespace FileSystem
{
    Result resolveFile(const TaskContext& ctx, fs::path& file);
    Result resolveFolder(const TaskContext& ctx, fs::path& folder);
    Utf8   normalizeSystemMessage(const Utf8& msg);
    Utf8   normalizeSystemMessage(std::error_code ec);
    void   collectSwagFilesRec(const TaskContext& ctx, const fs::path& folder, std::vector<fs::path>& files);
}

SWC_END_NAMESPACE()
