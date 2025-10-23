#pragma once
#include "Lexer/SourceFile.h"

using FileRef = uint32_t;

class FileManager
{
    std::vector<std::unique_ptr<SourceFile>> files_;
    std::mutex                               mutex_;

public:
    FileRef addFile(fs::path path);

    const std::vector<std::unique_ptr<SourceFile>>& files() const { return files_; }
    SourceFile*                                     file(FileRef ref) const { return files_[ref].get(); }
};
