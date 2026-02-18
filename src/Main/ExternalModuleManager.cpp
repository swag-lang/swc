#include "pch.h"
#include "Main/ExternalModuleManager.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

bool ExternalModuleManager::findLoadedModule(void*& outModuleHandle, std::string_view moduleName) const
{
    outModuleHandle = nullptr;
    for (const ModuleEntry& loadedModule : modules_)
    {
        if (loadedModule.moduleName == moduleName)
        {
            outModuleHandle = loadedModule.moduleHandle;
            return true;
        }
    }

    return false;
}

bool ExternalModuleManager::loadModule(void*& outModuleHandle, std::string_view moduleName)
{
    outModuleHandle = nullptr;
    if (moduleName.empty())
        return false;

    std::unique_lock lock(mutex_);
    if (findLoadedModule(outModuleHandle, moduleName))
        return true;

    if (!Os::loadExternalModule(outModuleHandle, moduleName))
        return false;

    modules_.push_back({.moduleName = Utf8{moduleName}, .moduleHandle = outModuleHandle});
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
