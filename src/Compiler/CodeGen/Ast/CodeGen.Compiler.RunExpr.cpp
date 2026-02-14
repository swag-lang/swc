#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroOpBits bitsForChunk(uint32_t chunkSize)
    {
        switch (chunkSize)
        {
            case 1:
                return MicroOpBits::B8;
            case 2:
                return MicroOpBits::B16;
            case 4:
                return MicroOpBits::B32;
            case 8:
                return MicroOpBits::B64;
            default:
                SWC_UNREACHABLE();
        }
    }

    void emitStructCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcReg, MicroReg tmpReg, uint32_t sizeInBytes)
    {
        auto&    builder = codeGen.builder();
        uint64_t offset  = 0;
        uint32_t remain  = sizeInBytes;

        while (remain >= 8)
        {
            builder.encodeLoadRegMem(tmpReg, srcReg, offset, MicroOpBits::B64, EncodeFlagsE::Zero);
            builder.encodeLoadMemReg(dstReg, offset, tmpReg, MicroOpBits::B64, EncodeFlagsE::Zero);
            offset += 8;
            remain -= 8;
        }

        if (remain >= 4)
        {
            builder.encodeLoadRegMem(tmpReg, srcReg, offset, MicroOpBits::B32, EncodeFlagsE::Zero);
            builder.encodeLoadMemReg(dstReg, offset, tmpReg, MicroOpBits::B32, EncodeFlagsE::Zero);
            offset += 4;
            remain -= 4;
        }

        if (remain >= 2)
        {
            builder.encodeLoadRegMem(tmpReg, srcReg, offset, MicroOpBits::B16, EncodeFlagsE::Zero);
            builder.encodeLoadMemReg(dstReg, offset, tmpReg, MicroOpBits::B16, EncodeFlagsE::Zero);
            offset += 2;
            remain -= 2;
        }

        if (remain >= 1)
        {
            builder.encodeLoadRegMem(tmpReg, srcReg, offset, MicroOpBits::B8, EncodeFlagsE::Zero);
            builder.encodeLoadMemReg(dstReg, offset, tmpReg, MicroOpBits::B8, EncodeFlagsE::Zero);
        }
    }
}

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    auto&              ctx      = codeGen.ctx();
    const auto&        callConv = CallConv::host();
    MicroInstrBuilder& builder  = codeGen.builder();
    const SemaNodeView exprView(codeGen.sema(), nodeExprRef);
    if (exprView.cst && exprView.type && !exprView.type->isStruct())
    {
        RESULT_VERIFY(codeGen.emitConstReturnValue(exprView));
    }
    else if (exprView.type && exprView.type->isStruct())
    {
        const uint32_t structSize = static_cast<uint32_t>(exprView.type->sizeOf(ctx));
        const auto     passing    = callConv.classifyStructReturnPassing(structSize);

        if (passing == StructArgPassingKind::ByReference)
        {
            SWC_ASSERT(!callConv.intArgRegs.empty());
            const MicroReg hiddenRetPtrReg = callConv.intArgRegs[0];

            MicroReg srcReg = MicroReg::invalid();
            MicroReg tmpReg = MicroReg::invalid();
            SWC_ASSERT(callConv.tryPickIntScratchRegs(srcReg, tmpReg, std::span{&hiddenRetPtrReg, 1}));

            if (exprView.cst && exprView.cst->isStruct())
            {
                const ByteSpan bytes = exprView.cst->getStruct();
                if (bytes.data() && bytes.size() >= structSize)
                {
                    builder.encodeLoadRegImm(srcReg, reinterpret_cast<uint64_t>(bytes.data()), MicroOpBits::B64, EncodeFlagsE::Zero);
                    emitStructCopy(codeGen, hiddenRetPtrReg, srcReg, tmpReg, structSize);
                }
            }
            else if (const auto* payload = codeGen.payload(nodeExprRef); payload && payload->kind == CodeGenNodePayloadKind::DerefPointerStorageU64)
            {
                builder.encodeLoadRegImm(srcReg, payload->valueU64, MicroOpBits::B64, EncodeFlagsE::Zero);
                builder.encodeLoadRegMem(srcReg, srcReg, 0, MicroOpBits::B64, EncodeFlagsE::Zero);
                emitStructCopy(codeGen, hiddenRetPtrReg, srcReg, tmpReg, structSize);
            }
        }
        else
        {
            SWC_ASSERT(structSize == 1 || structSize == 2 || structSize == 4 || structSize == 8);
            const MicroOpBits retBits = bitsForChunk(structSize);

            if (exprView.cst && exprView.cst->isStruct())
            {
                const ByteSpan bytes = exprView.cst->getStruct();
                if (bytes.data() && bytes.size() >= structSize)
                {
                    uint64_t raw = 0;
                    std::memcpy(&raw, bytes.data(), structSize);
                    builder.encodeLoadRegImm(callConv.intReturn, raw, retBits, EncodeFlagsE::Zero);
                }
            }
            else if (const auto* payload = codeGen.payload(nodeExprRef); payload && payload->kind == CodeGenNodePayloadKind::DerefPointerStorageU64)
            {
                MicroReg srcReg = MicroReg::invalid();
                MicroReg tmpReg = MicroReg::invalid();
                SWC_ASSERT(callConv.tryPickIntScratchRegs(srcReg, tmpReg));
                builder.encodeLoadRegImm(srcReg, payload->valueU64, MicroOpBits::B64, EncodeFlagsE::Zero);
                builder.encodeLoadRegMem(srcReg, srcReg, 0, MicroOpBits::B64, EncodeFlagsE::Zero);
                builder.encodeLoadRegMem(callConv.intReturn, srcReg, 0, retBits, EncodeFlagsE::Zero);
            }
        }
    }

    builder.encodeRet(EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
