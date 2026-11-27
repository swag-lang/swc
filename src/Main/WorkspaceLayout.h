#pragma once
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

// Where the compiler writes what it did not receive: the artifacts of a build, and the caches it
// keeps between runs. A build fills these directories and `swc clean` empties them, so both read
// the layout from here rather than each spelling the names again.
//
// Imports read directly from their source workspace.
namespace WorkspaceLayout
{
    inline fs::path workspaceSourceGroupsDirectory(const fs::path& workspacePath)
    {
        const fs::path namespaces = workspacePath / "namespaces";
        std::error_code error;
        return fs::is_directory(namespaces, error) ? namespaces : workspacePath / "modules";
    }

    // Artifacts a workspace build publishes, and the intermediate files it does not.
    inline fs::path workspaceOutputDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".output").lexically_normal();
    }

    inline fs::path workspaceWorkDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".tmp").lexically_normal();
    }

    // Legacy binary dependency copies, retained here for swc clean.
    inline fs::path workspaceDependencyDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".dep").lexically_normal();
    }

    // Root of compiler-owned caches outside a workspace. Linux uses a verified private directory
    // for the current user; other hosts keep it under the system temporary directory. Only the
    // subdirectories below this root are removed wholesale.
    inline fs::path cacheRoot()
    {
#ifdef __linux__
        return Os::compilerCacheRoot();
#else
        return (Os::getTemporaryPath() / "swag").lexically_normal();
#endif
    }

    // Cached binary dependency copies from earlier versions.
    inline fs::path dependencyCacheRoot()
    {
        return (cacheRoot() / "dep").lexically_normal();
    }

    inline fs::path machineCacheRoot()
    {
        return (cacheRoot() / "machine").lexically_normal();
    }

    // Legacy cache entries record their last access time in this marker.
    inline constexpr std::string_view DEPENDENCY_CACHE_USED_MARKER = ".swc-used";

    inline fs::path dependencyCacheUsedMarkerPath(const fs::path& entryDir)
    {
        return (entryDir / fs::path(std::string(DEPENDENCY_CACHE_USED_MARKER))).lexically_normal();
    }

    // Calls 'visit' with every entry whose marker is at least 'days' old. Returns false when the
    // scan of the cache root failed partway, after the entries it had already reached.
    template<typename F>
    bool visitUnusedDependencyCacheEntries(const uint32_t days, F&& visit)
    {
        const auto      maxAge = std::chrono::seconds(86400ULL * days);
        const auto      now    = fs::file_time_type::clock::now();
        std::error_code ec;
        for (fs::directory_iterator it(dependencyCacheRoot(), fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return false;

            ec.clear();
            if (!it->is_directory(ec) || ec)
                continue;

            ec.clear();
            const auto usedTime = fs::last_write_time(dependencyCacheUsedMarkerPath(it->path()), ec);
            if (ec || std::chrono::duration_cast<std::chrono::seconds>(now - usedTime) < maxAge)
                continue;

            visit(it->path());
        }

        return true;
    }

    // Where compilers before 0.0.2 mirrored a script's dependencies: one directory per set of
    // imports, each with its own copy of every one of them. Nothing fills it any more, and it is
    // named here so that `swc clean --cache` can still give back the disk it holds.
    inline fs::path legacyScriptCacheRoot()
    {
        return (cacheRoot() / "scripts").lexically_normal();
    }
}

SWC_END_NAMESPACE();
