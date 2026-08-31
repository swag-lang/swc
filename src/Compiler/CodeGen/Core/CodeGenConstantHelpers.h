#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Compiler/CodeGen/Core/CodeGenNodePayload.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;

namespace CodeGenConstantHelpers
{
    ConstantRef ensureStaticPayloadConstant(CodeGen& codeGen, ConstantRef cstRef, TypeRef typeRef = TypeRef::invalid());
    ConstantRef materializeStaticPayloadConstant(CodeGen& codeGen, TypeRef typeRef, std::span<const std::byte> payload);
    ConstantRef materializeStaticArrayBufferConstant(CodeGen& codeGen, TypeRef elementTypeRef, std::span<const std::byte> payload, uint64_t count);
    ConstantRef materializeRuntimeBufferConstant(CodeGen& codeGen, TypeRef typeRef, const void* targetPtr, uint64_t count);
    ConstantRef materializeRuntimeStringConstant(CodeGen& codeGen, TypeRef typeRef, std::string_view value);
    // A struct or array constant reached through its address: the payload carries the register
    // the relocated pointer was loaded into, marked as an address rather than a value.
    CodeGenNodePayload makeAddressPayloadFromConstant(CodeGen& codeGen, ConstantRef cstRef);
    Result      loadTypeInfoConstantReg(MicroReg& outReg, CodeGen& codeGen, TypeRef typeRef);
}

SWC_END_NAMESPACE();
