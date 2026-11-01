#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;
struct NativeObjDescription;

class NativeObjFileWriter
{
public:
    explicit NativeObjFileWriter(NativeBackendBuilder& builder) : builder_(&builder) {}
    virtual ~NativeObjFileWriter() = default;

    static std::unique_ptr<NativeObjFileWriter> create(NativeBackendBuilder& builder);

    virtual Result buildObjectFile(ByteArray& outBytes, const NativeObjDescription& description) = 0;
    virtual Result writeObjectFile(const NativeObjDescription& description);

protected:
    NativeBackendBuilder* builder_ = nullptr;
};

SWC_END_NAMESPACE();
