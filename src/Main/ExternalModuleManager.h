#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class ExternalModuleManager
{
public:
    ExternalModuleManager() = default;

    void registerSearchPath(fs::path path);
    bool loadModule(void*& outModuleHandle, std::string_view moduleName);
    bool getFunctionAddress(void*& outFunctionAddress, std::string_view moduleName, std::string_view functionName);

private:
    struct ModuleEntry
    {
        Utf8  moduleName;
        void* moduleHandle = nullptr;
    };

    mutable std::mutex       mutex_;
    std::vector<ModuleEntry> modules_;
    std::vector<fs::path>    searchPaths_;
    std::unordered_set<fs::path> searchPathSet_;
};

SWC_END_NAMESPACE();
