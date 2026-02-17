#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class ExternalModuleManager
{
public:
    ExternalModuleManager() = default;

    bool loadModule(void*& outModuleHandle, std::string_view moduleName);
    bool getFunctionAddress(void*& outFunctionAddress, std::string_view moduleName, std::string_view functionName);

private:
    struct ModuleEntry
    {
        Utf8  moduleName;
        void* moduleHandle = nullptr;
    };

    bool findLoadedModule(void*& outModuleHandle, std::string_view moduleName) const;

    mutable std::mutex       mutex_;
    std::vector<ModuleEntry> modules_;
};

SWC_END_NAMESPACE();
