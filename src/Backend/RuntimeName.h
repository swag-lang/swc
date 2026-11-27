#pragma once
#include "Backend/RuntimeBackendConfig.h"
#include "Backend/RuntimeBase.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

// Compile-time execution uses the compiler host even when native output targets another OS.
inline constexpr Runtime::TargetOs hostTargetOs()
{
#ifdef _WIN32
    return Runtime::TargetOs::Windows;
#elif defined(__linux__)
    return Runtime::TargetOs::Linux;
#endif
}

inline Utf8 targetArchName(const Runtime::TargetArch targetArch)
{
    switch (targetArch)
    {
        case Runtime::TargetArch::X86_64:
            return "x86_64";
    }

    SWC_UNREACHABLE();
}

inline Utf8 backendKindName(const Runtime::BuildCfgBackendKind backendKind)
{
    switch (backendKind)
    {
        case Runtime::BuildCfgBackendKind::Executable:
            return "executable";
        case Runtime::BuildCfgBackendKind::None:
            return "source";
    }

    SWC_UNREACHABLE();
}

inline Utf8 optimLevelName(const Runtime::BuildCfgBackendOptimLevel level)
{
    switch (level)
    {
        case Runtime::BuildCfgBackendOptimLevel::O0:
            return "O0";
        case Runtime::BuildCfgBackendOptimLevel::O1:
            return "O1";
        case Runtime::BuildCfgBackendOptimLevel::O2:
            return "O2";
    }

    SWC_UNREACHABLE();
}

inline Utf8 inlineModeName(const Runtime::BuildCfgBackendInlineMode mode)
{
    switch (mode)
    {
        case Runtime::BuildCfgBackendInlineMode::Never:
            return "never";
        case Runtime::BuildCfgBackendInlineMode::MarkedOnly:
            return "marked-only";
        case Runtime::BuildCfgBackendInlineMode::Auto:
            return "auto";
    }

    SWC_UNREACHABLE();
}

inline Utf8 targetOsName(const Runtime::TargetOs value)
{
    switch (value)
    {
        case Runtime::TargetOs::Windows:
            return "Windows";
        case Runtime::TargetOs::Linux:
            return "Linux";
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
