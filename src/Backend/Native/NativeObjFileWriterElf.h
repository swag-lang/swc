#pragma once
#include "Backend/Native/NativeObjFileWriter.h"

SWC_BEGIN_NAMESPACE();

class NativeObjFileWriterElf final : public NativeObjFileWriter
{
public:
    explicit NativeObjFileWriterElf(NativeBackendBuilder& builder) : NativeObjFileWriter(builder) {}
    Result buildObjectFile(ByteArray& outBytes, const NativeObjDescription& description) override;
};

SWC_END_NAMESPACE();
