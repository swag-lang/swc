#include "pch.h"
#include "Main/FileManager.h"
SWC_BEGIN_NAMESPACE()

FileRef FileManager::addFile(fs::path path)
{
    std::unique_lock lock(mutex_);

    path          = fs::absolute(path);
    const auto it = paths_.find(path);
    if (it != paths_.end())
        return it->second;

    const auto fileRef = static_cast<FileRef>(files_.size());
    paths_[path]       = fileRef;
    files_.emplace_back(std::make_unique<SourceFile>(std::move(path)));
    return fileRef;
}

SWC_END_NAMESPACE()
