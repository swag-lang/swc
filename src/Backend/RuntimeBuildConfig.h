#pragma once
#include "Backend/RuntimeAttribute.h"
#include "Backend/RuntimeBackendConfig.h"
#include "Backend/RuntimeBase.h"
#include "Backend/RuntimeDocConfig.h"
#include "Backend/RuntimeSafety.h"

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    inline constexpr String DEFAULT_REGISTERED_BUILD_CFGS = {
        .ptr    = "devmode|release",
        .length = 15,
    };

    // Each field lists warning identifiers separated with '|', and accepts 'all' to name
    // every warning at once. A field that names a warning outranks a field that says 'all',
    // whichever field it is.
    struct BuildCfgWarnings
    {
        String asErrors;
        String asWarnings;
        String disabled;
    };

    struct BuildCfg
    {
        uint32_t moduleVersion  = 0;
        uint32_t moduleRevision = 0;
        uint32_t moduleBuildNum = 0;
        String   moduleNamespace;
        bool     embeddedImports     = false;
        bool     ignoreInWorkspace   = false;
        bool     publishDependencies = false;

        uint32_t   tempAllocatorCapacity     = 4u * 1024u * 1024u;
        uint32_t   errorAllocatorCapacity    = 16u * 1024u;
        SafetyWhat safetyGuards              = SafetyWhat::All;
        SafetyWhat sanityGuards              = SafetyWhat::All;
        bool       allocatorCaptureStack     = false;
        bool       allocatorLeaks            = true;
        bool       allocatorTrackAllocations = false;
        bool       allocatorElectricMode     = false;
        bool       allocatorFillMemory       = false;
        bool       errorStackTrace           = true;

        BuildCfgWarnings warnings;

        BuildCfgBackendKind    backendKind    = BuildCfgBackendKind::Executable;
        BuildCfgBackendSubKind backendSubKind = BuildCfgBackendSubKind::Console;

        String          name;
        String          outDir;
        String          workDir;
        BuildCfgBackend backend;

        String         repoPath;
        String         resAppIcoFileName;
        String         resAppName;
        String         resAppDescription;
        String         resAppCompany;
        String         resAppCopyright;
        BuildCfgGenDoc genDoc;
        String         registeredConfigs = DEFAULT_REGISTERED_BUILD_CFGS;
    };
}

SWC_END_NAMESPACE();
