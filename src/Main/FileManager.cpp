#include "pch.h"
#include "Main/FileManager.h"

SWC_BEGIN_NAMESPACE();

FileRef FileManager::addFile(fs::path path)
{
    std::unique_lock lock(mutex_);

    path          = fs::absolute(path);
    const auto it = paths_.find(path);
    if (it != paths_.end())
        return it->second;

    const auto fileRef = static_cast<FileRef>(files_.size() + 1);
    paths_[path]       = fileRef;

    files_.emplace_back(std::make_unique<SourceFile>(std::move(path)));
    return fileRef;
}

std::vector<SourceFile*> FileManager::files() const
{
    std::shared_lock lock(mutex_);

    std::vector<SourceFile*> result;
    result.reserve(files_.size());
    for (const auto& f : files_)
        result.push_back(f.get());

    return result;
}

SWC_END_NAMESPACE();
