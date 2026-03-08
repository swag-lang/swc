#include "pch.h"
#include "Backend/Native/NativeBackend_Priv.h"

SWC_BEGIN_NAMESPACE();

namespace NativeBackendDetail
{
    std::unique_ptr<NativeObjectFileWriter> NativeObjectFileWriter::create(NativeBackendBuilder& builder, const Runtime::TargetOs targetOs)
    {
        SWC_UNUSED(builder);

        switch (targetOs)
        {
            case Runtime::TargetOs::Windows:
                return createNativeObjectFileWriterWindowsCoff(builder);

            case Runtime::TargetOs::Linux:
                return {};

            default:
                return {};
        }
    }
}

SWC_END_NAMESPACE();
