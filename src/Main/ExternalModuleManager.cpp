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

void ExternalModuleManager::registerDependencies(Utf8 moduleName, std::vector<Utf8> dependencies)
{
    const std::unique_lock lock(mutex_);
    for (DependencyEntry& entry : dependencies_)
    {
        if (entry.moduleName != moduleName)
            continue;
        entry.dependencies = std::move(dependencies);
        return;
    }
    dependencies_.push_back({std::move(moduleName), std::move(dependencies)});
}

bool ExternalModuleManager::loadModule(void*& outModuleHandle, const std::string_view moduleName)
{
    const std::unique_lock lock(mutex_);
    std::vector<std::string_view> activeModules;
    return loadModuleLocked(outModuleHandle, moduleName, activeModules);
}

bool ExternalModuleManager::loadModuleLocked(void*& outModuleHandle, const std::string_view moduleName, std::vector<std::string_view>& activeModules)
{
    outModuleHandle = nullptr;
    if (moduleName.empty())
        return false;

    const fs::path requestedPath{Utf8(moduleName).c_str()};

    for (const ModuleEntry& loadedModule : modules_)
    {
        if (loadedModule.moduleName != moduleName)
            continue;

        outModuleHandle = loadedModule.moduleHandle;
        return true;
    }

    // dlopen searches DT_NEEDED using the loader's paths, not our registered workspace
    // directories. Load the resolved dependency graph first so each SONAME is available.
    if (std::ranges::find(activeModules, moduleName) != activeModules.end())
        return false;
    activeModules.push_back(moduleName);
    for (const DependencyEntry& entry : dependencies_)
    {
        if (entry.moduleName != moduleName)
            continue;
        for (const Utf8& dependency : entry.dependencies)
        {
            void* dependencyHandle = nullptr;
            if (!loadModuleLocked(dependencyHandle, dependency.view(), activeModules))
            {
                activeModules.pop_back();
                return false;
            }
        }
        break;
    }
    activeModules.pop_back();

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
