#pragma once
#include "Lexer/SourceFile.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;

class FileManager
{
    std::vector<std::unique_ptr<SourceFile>> files_;
    std::unordered_map<fs::path, FileRef>    paths_;
    mutable std::shared_mutex                mutex_;

public:
    FileRef                  addFile(fs::path path);
    std::vector<SourceFile*> files() const;
    Result                   collectFiles(const TaskContext& ctx);

    SourceFile* file(FileRef ref) const
    {
        std::shared_lock lock(mutex_);
        SWC_ASSERT(ref != INVALID_REF);
        return files_[ref - 1].get();
    }
};

SWC_END_NAMESPACE()
