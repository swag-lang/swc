#pragma once
#include <span>

#include "Support/Core/RefTypes.h"
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_VALIDATE_NATIVE

class NativeValidate final
{
public:
    explicit NativeValidate(NativeBackendBuilder& builder);

    void validate() const;

private:
    bool isNativeStaticType(TypeRef typeRef) const;
    void validateRelocations(const MachineCode& code) const;
    void validateConstantRelocation(const MicroRelocation& relocation) const;
    void validateNativeStaticPayload(TypeRef typeRef, uint32_t shardIndex, Ref baseOffset, std::span<const std::byte> bytes) const;
    bool findDataSegmentRelocation(DataSegmentRef& outTargetRef, uint32_t shardIndex, uint32_t offset) const;
    bool findFunctionSymbolRelocation(const SymbolFunction*& outTargetSymbol, uint32_t shardIndex, uint32_t offset) const;

    NativeBackendBuilder* builder_ = nullptr;
};

#endif

SWC_END_NAMESPACE();
