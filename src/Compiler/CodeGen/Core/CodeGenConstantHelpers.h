#pragma once
#include "Support/Core/ByteSpan.h"
#include "Support/Core/RefTypes.h"
#include <cstdint>

SWC_BEGIN_NAMESPACE();

class CodeGen;

namespace CodeGenConstantHelpers
{
    ConstantRef ensureStaticPayloadConstant(CodeGen& codeGen, ConstantRef cstRef, TypeRef typeRef = TypeRef::invalid());
    ConstantRef materializeStaticPayloadConstant(CodeGen& codeGen, TypeRef typeRef, ByteSpan payload);
    ConstantRef materializeStaticArrayBufferConstant(CodeGen& codeGen, TypeRef elementTypeRef, ByteSpan payload, uint64_t count);
    ConstantRef materializeRuntimeBufferConstant(CodeGen& codeGen, TypeRef typeRef, const void* targetPtr, uint64_t count);
}

SWC_END_NAMESPACE();
