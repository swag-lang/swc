#include "pch.h"

#include "Context.h"
#include "FileSystem.h"
#include "Global.h"
#include "Main/CommandLine.h"
#include "Main/FileManager.h"

SWC_BEGIN_NAMESPACE()

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

Result FileManager::collectFiles(const Context& ctx)
{
    std::vector<fs::path> paths;

    // Collect direct files from the command line
    for (const auto& folder : ctx.cmdLine().directories)
        FileSystem::collectSwagFilesRec(ctx, folder, paths);
    for (const auto& file : ctx.cmdLine().files)
        paths.push_back(file);

    if (paths.empty())
    {
        const auto diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    // In single threaded mode, make paths order deterministic
    if (ctx.cmdLine().numCores == 1)
        std::ranges::sort(paths);

    // Register all files
    for (const auto& f : paths)
        addFile(f);

    return Result::Success;
}

SWC_END_NAMESPACE()
