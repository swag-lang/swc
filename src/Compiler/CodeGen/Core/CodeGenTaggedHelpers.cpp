#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenTaggedHelpers.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenNodePayload.h"
#include "Compiler/CodeGen/Core/CodeGenReferenceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Sema/Helpers/SemaTagged.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroOpBits tagBits(CodeGen& codeGen, const SymbolStruct& tagged)
    {
        return CodeGenTypeHelpers::bitsFromStorageSize(tagged.taggedTagSize(codeGen.ctx()));
    }

    void zeroExtendTag(CodeGen& codeGen, MicroReg dstReg, MicroReg srcReg, MicroOpBits bits)
    {
        if (bits == MicroOpBits::B64)
            codeGen.builder().emitLoadRegReg(dstReg, srcReg, MicroOpBits::B64);
        else
            codeGen.builder().emitLoadZeroExtendRegReg(dstReg, srcReg, MicroOpBits::B64, bits);
    }
}

MicroReg CodeGenTaggedHelpers::loadTagAt(CodeGen& codeGen, MicroReg unionAddressReg, const SymbolStruct& tagged)
{
    const MicroOpBits bits   = tagBits(codeGen, tagged);
    const MicroReg    tagReg = codeGen.nextVirtualIntRegister();
    if (bits == MicroOpBits::B64)
        codeGen.builder().emitLoadRegMem(tagReg, unionAddressReg, 0, MicroOpBits::B64);
    else
        codeGen.builder().emitLoadZeroExtendRegMem(tagReg, unionAddressReg, 0, MicroOpBits::B64, bits);
    return tagReg;
}

MicroReg CodeGenTaggedHelpers::loadTag(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef exprTypeRef, const SymbolStruct& tagged)
{
    CodeGenNodePayload valuePayload = payload;
    TypeRef            valueTypeRef = exprTypeRef;
    const TypeInfo*    valueType    = CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, valuePayload, valueTypeRef);
    SWC_ASSERT(valueType != nullptr);

    if (valueType->unwrapAliasTypeOrSelf(codeGen.ctx()).isValuePointer())
    {
        MicroReg pointerReg = valuePayload.reg;
        if (valuePayload.isAddress())
        {
            pointerReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(pointerReg, valuePayload.reg, 0, MicroOpBits::B64);
        }

        return loadTagAt(codeGen, pointerReg, tagged);
    }

    if (valuePayload.isAddress())
        return loadTagAt(codeGen, valuePayload.reg, tagged);

    // A small union travels in a register: the tag is its low bytes.
    const MicroReg tagReg = codeGen.nextVirtualIntRegister();
    zeroExtendTag(codeGen, tagReg, valuePayload.reg, tagBits(codeGen, tagged));
    return tagReg;
}

void CodeGenTaggedHelpers::emitJumpIfCase(CodeGen& codeGen, MicroReg tagReg, const SymbolStruct& tagged, std::span<const ConstantRef> values, MicroLabelRef targetLabel)
{
    const MicroOpBits bits = tagBits(codeGen, tagged);
    for (const ConstantRef value : values)
    {
        codeGen.builder().emitCmpRegImm(tagReg, ApInt(SemaTagged::valueBits(codeGen.ctx(), value), 64), bits);
        codeGen.builder().emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, targetLabel);
    }
}

SWC_END_NAMESPACE();
