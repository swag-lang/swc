#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Result.h"
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class NativeObjFileWriter
{
public:
    virtual ~NativeObjFileWriter() = default;

    static std::unique_ptr<NativeObjFileWriter> create(NativeBackendBuilder& builder);

    virtual Result buildObjectFile(ByteArray& outBytes, const NativeObjDescription& description) = 0;
    virtual Result writeObjectFile(const NativeObjDescription& description)                                   = 0;
};

SWC_END_NAMESPACE();
