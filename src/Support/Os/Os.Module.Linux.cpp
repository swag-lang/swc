#include "pch.h"
#include "Support/Os/Os.h"

#ifdef __linux__
#include <dlfcn.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    std::mutex            g_modulePathsMutex;
    std::vector<fs::path> g_modulePaths;

    void* loadModulePath(const fs::path& path)
    {
        return dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    }

    std::vector<fs::path> moduleSearchPaths()
    {
        const std::scoped_lock lock(g_modulePathsMutex);
        return g_modulePaths;
    }
}

void Os::registerExternalModuleSearchPath(const fs::path& path)
{
    if (path.empty())
        return;
    std::error_code error;
    const fs::path  absolute = fs::absolute(path, error).lexically_normal();
    if (error)
        return;
    const std::scoped_lock lock(g_modulePathsMutex);
    if (std::ranges::find(g_modulePaths, absolute) == g_modulePaths.end())
        g_modulePaths.push_back(absolute);
}

bool Os::loadExternalModule(void*& outModuleHandle, const std::string_view moduleName)
{
    outModuleHandle = nullptr;
    if (moduleName.empty() || moduleName.find('\0') != std::string_view::npos)
        return false;

    const fs::path requested{moduleName};
    const auto     filename = requested.filename().string();
    std::vector<fs::path> candidates{requested};
    if (!filename.ends_with(".so") && filename.find(".so.") == std::string::npos)
    {
        // Swag module artifacts keep their module name; system libraries commonly
        // add lib. Try both without changing explicit or versioned library names.
        candidates.push_back(requested.parent_path() / (filename + ".so"));
        if (!filename.starts_with("lib"))
            candidates.push_back(requested.parent_path() / ("lib" + filename + ".so"));
    }

    // Constructors can call back into host services: do not hold our path mutex in dlopen.
    const auto paths = requested.has_parent_path() ? std::vector<fs::path>{} : moduleSearchPaths();
    for (const auto& candidate : candidates)
    {
        if ((outModuleHandle = loadModulePath(candidate)))
            return true;
        for (const auto& directory : paths)
        {
            if ((outModuleHandle = loadModulePath(directory / candidate)))
                return true;
        }
    }
    return false;
}

bool Os::getExternalSymbolAddress(void*& outFunctionAddress, void* moduleHandle, const std::string_view functionName)
{
    outFunctionAddress = nullptr;
    if (!moduleHandle || functionName.empty() || functionName.find('\0') != std::string_view::npos)
        return false;
    const std::string name(functionName);
    dlerror();
    void* address = dlsym(moduleHandle, name.c_str());
    if (dlerror() || !address)
        return false;
    outFunctionAddress = address;
    return true;
}

SWC_END_NAMESPACE();
#endif
