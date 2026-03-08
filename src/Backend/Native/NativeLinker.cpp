#include "pch.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinkerCoff.h"

SWC_BEGIN_NAMESPACE();

std::unique_ptr<NativeLinker> NativeLinker::create(NativeBackendBuilder& builder)
{
    switch (builder.ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            return std::make_unique<NativeLinkerCoff>(builder);

        case Runtime::TargetOs::Linux:
            return {};

        default:
            return {};
    }
}

SWC_END_NAMESPACE();
