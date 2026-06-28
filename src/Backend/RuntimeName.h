#pragma once
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"
#include "Backend/Runtime.h"
#include "Support/Math/Hash.h"

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

inline Utf8 cpuVectorizeName(const Runtime::BuildCfgBackendCpuVectorize mode)
{
    switch (mode)
    {
        case Runtime::BuildCfgBackendCpuVectorize::None:
            return "none";
        case Runtime::BuildCfgBackendCpuVectorize::Sse2:
            return "sse2";
        case Runtime::BuildCfgBackendCpuVectorize::Avx2:
            return "avx2";
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

inline Utf8 runtimeHookSymbolName(std::string_view artifactName)
{
    Utf8 key = artifactName;
    key.make_lower();
    return std::format("__swc_rt_stage_{:08x}", Math::hash(key.view()));
}

SWC_END_NAMESPACE();
