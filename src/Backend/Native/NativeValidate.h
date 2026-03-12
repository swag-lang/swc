#pragma once
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_NATIVE_VALIDATION

class NativeValidate final
{
public:
    explicit NativeValidate(NativeBackendBuilder& builder);

    void validate() const;

private:
    bool isNativeStaticType(TypeRef typeRef) const;
    void validateRelocations(const SymbolFunction& owner, const MachineCode& code) const;
    bool validateConstantRelocation(const MicroRelocation& relocation) const;
    bool validateNativeStaticPayload(TypeRef typeRef, uint32_t shardIndex, Ref baseOffset, ByteSpan bytes) const;
    bool findDataSegmentRelocation(uint32_t& outTargetOffset, uint32_t shardIndex, uint32_t offset) const;

    NativeBackendBuilder& builder_;
};

#endif

SWC_END_NAMESPACE();
