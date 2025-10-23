#include "pch.h"
#include "Main/FileManager.h"

FileRef FileManager::addFile(fs::path path)
{
    std::lock_guard lock(mutex_);
    files_.emplace_back(std::make_unique<SourceFile>(std::move(path)));
    return static_cast<FileRef>(files_.size()) - 1;   
}
