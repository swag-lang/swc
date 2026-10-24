#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolStruct;
struct CodeGenNodePayload;

// A tagged union stores its tag at offset 0, so every read of the case is one small load.
namespace CodeGenTaggedHelpers
{
    // The tag of the union at 'unionAddressReg', zero-extended to 64 bits.
    MicroReg loadTagAt(CodeGen& codeGen, MicroReg unionAddressReg, const SymbolStruct& tagged);
    // The tag of the union an expression yields: the union itself, in memory or in a register,
    // or a pointer or reference to it.
    MicroReg loadTag(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef exprTypeRef, const SymbolStruct& tagged);
    // Jumps to 'targetLabel' when the tag is one of 'values'.
    void emitJumpIfCase(CodeGen& codeGen, MicroReg tagReg, const SymbolStruct& tagged, std::span<const ConstantRef> values, MicroLabelRef targetLabel);
}

SWC_END_NAMESPACE();
