#pragma once
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

// Where the compiler writes what it did not receive: the artifacts of a build, and the caches it
// keeps between runs. A build fills these directories and `swc clean` empties them, so both read
// the layout from here rather than each spelling the names again.
namespace WorkspaceLayout
{
    // Artifacts a workspace build publishes, and the intermediate files it does not.
    inline fs::path workspaceOutputDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".output").lexically_normal();
    }

    inline fs::path workspaceWorkDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".tmp").lexically_normal();
    }

    // Private copy of every dependency a workspace imports from outside itself, so that a build
    // consumes something it owns rather than a directory somebody else may rewrite under it.
    inline fs::path workspaceDependencyDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".dep").lexically_normal();
    }

    // Root of everything the compiler caches outside any workspace. It is shared with whatever
    // else a user keeps there, so only the subdirectories below are ever removed wholesale.
    inline fs::path cacheRoot()
    {
        return (Os::getTemporaryPath() / "swag").lexically_normal();
    }

    // One directory per build of a dependency, holding a copy of it. An entry is named after the
    // bytes it holds, so every script that imports the same build shares it and none of them can
    // observe it being filled.
    inline fs::path dependencyCacheRoot()
    {
        return (cacheRoot() / "dep").lexically_normal();
    }

    // Where an entry is assembled before it is renamed into place, which is the moment it starts
    // to exist for everyone else.
    inline fs::path dependencyCacheStagingRoot()
    {
        return (dependencyCacheRoot() / ".staging").lexically_normal();
    }

    // Written when an entry is published and re-dated every time one is used, so a cache can be
    // trimmed by what nothing has needed for a while. Its presence is also what tells a trim that
    // the directory is an entry rather than something else a user left here.
    inline constexpr std::string_view DEPENDENCY_CACHE_USED_MARKER = ".swc-used";

    // Where compilers before 0.0.2 mirrored a script's dependencies: one directory per set of
    // imports, each with its own copy of every one of them. Nothing fills it any more, and it is
    // named here so that `swc clean --cache` can still give back the disk it holds.
    inline fs::path legacyScriptCacheRoot()
    {
        return (cacheRoot() / "scripts").lexically_normal();
    }
}

SWC_END_NAMESPACE();
