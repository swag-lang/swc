#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/ByteSpan.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;

namespace CodeGenConstantHelpers
{
    ConstantRef ensureStaticPayloadConstant(CodeGen& codeGen, ConstantRef cstRef, TypeRef typeRef = TypeRef::invalid());
    ConstantRef materializeStaticPayloadConstant(CodeGen& codeGen, TypeRef typeRef, ByteSpan payload);
    ConstantRef materializeStaticArrayBufferConstant(CodeGen& codeGen, TypeRef elementTypeRef, ByteSpan payload, uint64_t count);
    ConstantRef materializeRuntimeBufferConstant(CodeGen& codeGen, TypeRef typeRef, const void* targetPtr, uint64_t count);
    ConstantRef materializeRuntimeStringConstant(CodeGen& codeGen, TypeRef typeRef, std::string_view value);
    Result      loadTypeInfoConstantReg(MicroReg& outReg, CodeGen& codeGen, TypeRef typeRef);
}

SWC_END_NAMESPACE();
