#pragma once

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace FileSystem
{
    Result resolveFile(TaskContext& ctx, fs::path& file);
    Result resolveFolder(TaskContext& ctx, fs::path& folder);
    Utf8   formatFileName(const TaskContext* ctx, const fs::path& filePath);
    Utf8   formatFileLocation(const TaskContext* ctx, const fs::path& filePath, uint32_t line, uint32_t column = 0, uint32_t columnEnd = 0);
    Utf8   normalizeSystemMessage(const Utf8& msg);
    Utf8   normalizeSystemMessage(std::error_code ec);
    void   collectSwagFilesRec(const TaskContext& ctx, const fs::path& folder, std::vector<fs::path>& files, bool canFilter = true);
}

SWC_END_NAMESPACE();
