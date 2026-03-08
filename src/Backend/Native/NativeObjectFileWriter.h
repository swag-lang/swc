#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace NativeBackendDetail
{
    class NativeObjectFileWriter
    {
    public:
        virtual ~NativeObjectFileWriter() = default;

        static std::unique_ptr<NativeObjectFileWriter> create(NativeBackendBuilder& builder, Runtime::TargetOs targetOs);

        virtual bool writeObjectFile(const NativeObjDescription& description) = 0;
    };

    std::unique_ptr<NativeObjectFileWriter> createNativeObjectFileWriterWindowsCoff(NativeBackendBuilder& builder);
}

SWC_END_NAMESPACE();
