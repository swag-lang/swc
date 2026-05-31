#include "pch.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

void ExternalModuleManager::registerSearchPath(fs::path path)
{
    if (path.empty())
        return;

    path = FileSystem::normalizePath(path);

    const std::unique_lock lock(mutex_);
    if (!searchPathSet_.insert(path).second)
        return;

    Os::registerExternalModuleSearchPath(path);
    searchPaths_.push_back(std::move(path));
}

bool ExternalModuleManager::loadModule(void*& outModuleHandle, std::string_view moduleName)
{
    outModuleHandle = nullptr;
    if (moduleName.empty())
        return false;

    const fs::path requestedPath{Utf8(moduleName).c_str()};

    const std::unique_lock lock(mutex_);
    for (const ModuleEntry& loadedModule : modules_)
    {
        if (loadedModule.moduleName != moduleName)
            continue;

        outModuleHandle = loadedModule.moduleHandle;
        return true;
    }

    if (!Os::loadExternalModule(outModuleHandle, moduleName))
    {
        if (requestedPath.has_parent_path())
            return false;

        for (const fs::path& searchPath : searchPaths_)
        {
            fs::path candidatePath = searchPath / requestedPath.filename();
            if (!Os::loadExternalModule(outModuleHandle, Utf8(candidatePath).view()))
                continue;

            ModuleEntry moduleEntry{.moduleName = Utf8(moduleName), .moduleHandle = outModuleHandle};
            modules_.push_back(std::move(moduleEntry));
            return true;
        }

        return false;
    }

    ModuleEntry moduleEntry{.moduleName = Utf8(moduleName), .moduleHandle = outModuleHandle};
    modules_.push_back(std::move(moduleEntry));
    return true;
}

bool ExternalModuleManager::getFunctionAddress(void*& outFunctionAddress, std::string_view moduleName, std::string_view functionName)
{
    outFunctionAddress = nullptr;

    void* moduleHandle = nullptr;
    if (!loadModule(moduleHandle, moduleName))
        return false;

    return Os::getExternalSymbolAddress(outFunctionAddress, moduleHandle, functionName);
}

SWC_END_NAMESPACE();
