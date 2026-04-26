#pragma once
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

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
        case Runtime::BuildCfgBackendKind::SharedLibrary:
            return "shared-library";
        case Runtime::BuildCfgBackendKind::StaticLibrary:
            return "static-library";
        case Runtime::BuildCfgBackendKind::Export:
            return "export";
        case Runtime::BuildCfgBackendKind::None:
            return "none";
    }

    SWC_UNREACHABLE();
}

inline Utf8 targetOsName(const Runtime::TargetOs value)
{
    switch (value)
    {
        case Runtime::TargetOs::Windows:
            return "Windows";
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
