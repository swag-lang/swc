#pragma once

#include "Backend/Native/NativeBackendTypes.h"

SWC_BEGIN_NAMESPACE();

class NativeObjectFileWriter
{
public:
    virtual ~NativeObjectFileWriter() = default;

    static std::unique_ptr<NativeObjectFileWriter> create(NativeBackendBuilder& builder);

    virtual bool writeObjectFile(const NativeObjDescription& description) = 0;
};

std::unique_ptr<NativeObjectFileWriter> createNativeObjectFileWriterWindowsCoff(NativeBackendBuilder& builder);

SWC_END_NAMESPACE();
