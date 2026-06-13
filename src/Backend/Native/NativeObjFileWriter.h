#pragma once
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class NativeObjFileWriter
{
public:
    virtual ~NativeObjFileWriter() = default;

    static std::unique_ptr<NativeObjFileWriter> create(NativeBackendBuilder& builder);

    virtual Result buildObjectFile(std::vector<std::byte>& outBytes, const NativeObjDescription& description) = 0;
    virtual Result writeObjectFile(const NativeObjDescription& description)                                   = 0;
};

SWC_END_NAMESPACE();
