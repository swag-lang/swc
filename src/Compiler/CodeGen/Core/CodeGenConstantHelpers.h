#pragma once
#include <cstdint>
#include "Support/Core/ByteSpan.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;

namespace CodeGenConstantHelpers
{
    ConstantRef materializeStaticPayloadConstant(CodeGen& codeGen, TypeRef typeRef, ByteSpan payload);
    ConstantRef materializeRuntimeBufferConstant(CodeGen& codeGen, TypeRef typeRef, const void* targetPtr, uint64_t count);
}

SWC_END_NAMESPACE();
