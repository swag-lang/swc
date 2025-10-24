#pragma once
#include "Core/Types.h"
#include "Lexer/SourceFile.h"

SWC_BEGIN_NAMESPACE();

class FileManager
{
    std::vector<std::unique_ptr<SourceFile>> files_;
    std::unordered_map<fs::path, FileRef>    paths_;
    mutable std::shared_mutex                mutex_;

public:
    FileRef addFile(fs::path path);

    std::vector<SourceFile*> files() const
    {
        std::shared_lock lock(mutex_);

        std::vector<SourceFile*> result;
        result.reserve(files_.size());
        for (const auto& f : files_)
            result.push_back(f.get());
        return result;
    }

    SourceFile* file(FileRef ref) const
    {
        std::shared_lock lock(mutex_);
        return files_[ref].get();
    }
};

SWC_END_NAMESPACE();
