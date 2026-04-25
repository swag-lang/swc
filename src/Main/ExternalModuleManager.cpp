#include "pch.h"
#include "Main/ExternalModuleManager.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

bool ExternalModuleManager::loadModule(void*& outModuleHandle, std::string_view moduleName)
{
    outModuleHandle = nullptr;
    if (moduleName.empty())
        return false;

    const std::unique_lock lock(mutex_);
    for (const ModuleEntry& loadedModule : modules_)
    {
        if (loadedModule.moduleName != moduleName)
            continue;

        outModuleHandle = loadedModule.moduleHandle;
        return true;
    }

    if (!Os::loadExternalModule(outModuleHandle, moduleName))
        return false;

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
