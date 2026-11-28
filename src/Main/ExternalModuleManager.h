#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class ExternalModuleManager
{
public:
    ExternalModuleManager() = default;

    void registerSearchPath(fs::path path);
    void registerDependencies(Utf8 moduleName, std::vector<Utf8> dependencies);
    bool loadModule(void*& outModuleHandle, std::string_view moduleName);
    bool getFunctionAddress(void*& outFunctionAddress, std::string_view moduleName, std::string_view functionName);

private:
    struct ModuleEntry
    {
        Utf8  moduleName;
        void* moduleHandle = nullptr;
    };

    struct DependencyEntry
    {
        Utf8              moduleName;
        std::vector<Utf8> dependencies;
    };

    bool loadModuleLocked(void*& outModuleHandle, std::string_view moduleName, std::vector<std::string_view>& activeModules);

    std::vector<DependencyEntry> dependencies_;
    mutable std::mutex           mutex_;
    std::vector<ModuleEntry>     modules_;
    std::vector<fs::path>        searchPaths_;
    std::unordered_set<fs::path> searchPathSet_;
};

SWC_END_NAMESPACE();
