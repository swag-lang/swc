#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/CodeGen/Micro/MicroInstrHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstParenExpr::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.curNodeView().typeRef);
    return Result::Continue;
}

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    auto&              ctx      = codeGen.ctx();
    const auto&        callConv = CallConv::host();
    MicroInstrBuilder& builder  = codeGen.builder();
    const auto         exprView = codeGen.nodeView(nodeExprRef);
    SWC_ASSERT(exprView.type);

    const auto* payload = codeGen.payload(nodeExprRef);
    SWC_ASSERT(payload != nullptr);
    const MicroReg payloadReg = CodeGen::payloadVirtualReg(*payload);

    if (!exprView.type->isStruct())
    {
        MicroReg srcReg = MicroReg::invalid();
        MicroReg tmpReg = MicroReg::invalid();
        SWC_ASSERT(callConv.tryPickIntScratchRegs(srcReg, tmpReg));
        builder.encodeLoadRegReg(srcReg, payloadReg, MicroOpBits::B64, EncodeFlagsE::Zero);

        if (exprView.type->isVoid())
        {
            builder.encodeRet(EncodeFlagsE::Zero);
            return Result::Continue;
        }

        if (exprView.type->isFloat())
        {
            const MicroOpBits bits = microOpBitsFromBitWidth(exprView.type->payloadFloatBits());
            SWC_ASSERT(bits == MicroOpBits::B32 || bits == MicroOpBits::B64);
            builder.encodeLoadRegMem(callConv.floatReturn, srcReg, 0, bits, EncodeFlagsE::Zero);
            builder.encodeRet(EncodeFlagsE::Zero);
            return Result::Continue;
        }

        MicroOpBits bits = MicroOpBits::B64;
        if (exprView.type->isBool())
            bits = MicroOpBits::B8;
        else if (exprView.type->isCharRune())
            bits = MicroOpBits::B32;
        else if (exprView.type->isIntLike())
            bits = microOpBitsFromBitWidth(exprView.type->payloadIntLikeBits());
        SWC_ASSERT(bits != MicroOpBits::Zero);

        builder.encodeLoadRegMem(callConv.intReturn, srcReg, 0, bits, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);
        return Result::Continue;
    }

    const uint32_t structSize = static_cast<uint32_t>(exprView.type->sizeOf(ctx));
    const auto     passing    = callConv.classifyStructReturnPassing(structSize);
    SWC_ASSERT(passing == StructArgPassingKind::ByReference); // TODO: replace assert with a proper codegen diagnostic.

    SWC_ASSERT(!callConv.intArgRegs.empty());
    const MicroReg hiddenRetPtrReg = callConv.intArgRegs[0];

    MicroReg srcReg = MicroReg::invalid();
    MicroReg tmpReg = MicroReg::invalid();
    SWC_ASSERT(callConv.tryPickIntScratchRegs(srcReg, tmpReg, std::span{&hiddenRetPtrReg, 1}));

    builder.encodeLoadRegReg(srcReg, payloadReg, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadRegMem(srcReg, srcReg, 0, MicroOpBits::B64, EncodeFlagsE::Zero);
    MicroInstrHelpers::emitMemCopy(builder, hiddenRetPtrReg, srcReg, tmpReg, structSize);

    builder.encodeRet(EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
