#pragma once

#include "Backend/Native/NativeBackendTypes.h"

SWC_BEGIN_NAMESPACE();

class NativeObjFileWriter
{
public:
    virtual ~NativeObjFileWriter() = default;

    static std::unique_ptr<NativeObjFileWriter> create(NativeBackendBuilder& builder);

    virtual bool writeObjectFile(const NativeObjDescription& description) = 0;
};

SWC_END_NAMESPACE();
