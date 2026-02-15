#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/CodeGen/Micro/MicroInstrHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    auto&              ctx      = codeGen.ctx();
    const auto&        callConv = CallConv::host();
    MicroInstrBuilder& builder  = codeGen.builder();
    const auto         exprView = codeGen.nodeView(nodeExprRef);
    SWC_ASSERT(exprView.type);

    const auto* payload = codeGen.payload(nodeExprRef);
    SWC_ASSERT(payload != nullptr);
    const MicroReg payloadReg = payload->reg;
    const bool     isLValue   = codeGen.sema().isLValue(nodeExprRef);

    SWC_ASSERT(!callConv.intArgRegs.empty());
    const MicroReg outputStorageReg = callConv.intArgRegs[0];
    const auto     abiRet           = ABITypeNormalize::normalize(ctx, callConv, exprView.typeRef, ABITypeNormalize::Usage::Return);

    if (abiRet.isVoid)
    {
        builder.encodeRet(EncodeFlagsE::Zero);
        return Result::Continue;
    }

    if (abiRet.isIndirect)
    {
        SWC_ASSERT(abiRet.indirectSize != 0);
        MicroReg srcReg = MicroReg::invalid();
        MicroReg tmpReg = MicroReg::invalid();
        SWC_ASSERT(callConv.tryPickIntScratchRegs(srcReg, tmpReg, std::span{&outputStorageReg, 1}));
        builder.encodeLoadRegReg(srcReg, payloadReg, MicroOpBits::B64, EncodeFlagsE::Zero);
        MicroInstrHelpers::emitMemCopy(builder, outputStorageReg, srcReg, tmpReg, abiRet.indirectSize);
        builder.encodeRet(EncodeFlagsE::Zero);
        return Result::Continue;
    }

    const MicroOpBits bits = microOpBitsFromBitWidth(abiRet.numBits);
    SWC_ASSERT(bits != MicroOpBits::Zero);
    if (abiRet.isFloat)
    {
        if (isLValue)
            builder.encodeLoadRegMem(callConv.floatReturn, payloadReg, 0, bits, EncodeFlagsE::Zero);
        else
            builder.encodeLoadRegReg(callConv.floatReturn, payloadReg, bits, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(outputStorageReg, 0, callConv.floatReturn, bits, EncodeFlagsE::Zero);
    }
    else
    {
        if (isLValue)
            builder.encodeLoadRegMem(callConv.intReturn, payloadReg, 0, bits, EncodeFlagsE::Zero);
        else
            builder.encodeLoadRegReg(callConv.intReturn, payloadReg, bits, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(outputStorageReg, 0, callConv.intReturn, bits, EncodeFlagsE::Zero);
    }

    builder.encodeRet(EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
