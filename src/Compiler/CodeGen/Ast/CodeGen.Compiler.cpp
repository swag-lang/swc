#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroAbiCall.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.h"

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

        const auto emitChunk = [&](const uint32_t chunk) {
            const MicroOpBits bits = bitsForChunk(chunk);
            builder.encodeLoadRegMem(tmpReg, srcReg, offset, bits, EncodeFlagsE::Zero);
            builder.encodeLoadMemReg(dstReg, offset, tmpReg, bits, EncodeFlagsE::Zero);
            offset += chunk;
            remain -= chunk;
        };

        while (remain >= 8)
            emitChunk(8);
        if (remain >= 4)
            emitChunk(4);
        if (remain >= 2)
            emitChunk(2);
        if (remain >= 1)
            emitChunk(1);
    }
}

Result AstIntrinsicCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.sema().token(codeRef());
    if (tok.id != TokenId::IntrinsicCompiler)
        return Result::Continue;

    const auto compilerIfAddress = reinterpret_cast<uint64_t>(&codeGen.ctx().compiler().runtimeCompiler());
    const auto nodeView          = SemaNodeView(codeGen.sema(), codeGen.visit().currentNodeRef());
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::AddressValue, compilerIfAddress, nodeView.typeRef);
    return Result::Continue;
}

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* leftPayload = codeGen.payload(nodeLeftRef);
    if (!leftPayload || leftPayload->kind != CodeGenNodePayloadKind::AddressValue)
        return Result::Continue;

    const SemaNodeView rightView(codeGen.sema(), nodeRightRef);

    const Symbol* methodSym = rightView.sym;
    if (!methodSym && !rightView.symList.empty())
        methodSym = rightView.symList.front();
    if (!methodSym || !methodSym->isFunction())
        return Result::Continue;

    if (methodSym->name(codeGen.ctx()) != "getBuildCfg")
        return Result::Continue;

    auto& runtimeCompiler = codeGen.ctx().compiler().runtimeCompiler();
    SWC_ASSERT(runtimeCompiler.itable != nullptr);
    const auto targetAddress = reinterpret_cast<uint64_t>(runtimeCompiler.itable[1]);
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::ExternalFunctionAddress, targetAddress);
    return Result::Continue;
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* calleePayload = codeGen.payload(nodeExprRef);
    if (!calleePayload || calleePayload->kind != CodeGenNodePayloadKind::ExternalFunctionAddress)
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    collectArguments(args, codeGen.ast());
    SWC_ASSERT(args.empty());
    if (!args.empty())
        return Result::Continue;

    auto* resultStorage = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage      = 0;

    const MicroABICallReturn ret = {
        .valuePtr   = resultStorage,
        .isVoid     = false,
        .isFloat    = false,
        .isIndirect = false,
        .numBits    = 64,
    };

    emitMicroABICallByAddress(codeGen.builder(), CallConvKind::Host, calleePayload->valueU64, std::span<const MicroABICallArg>{}, ret);

    const auto nodeView = SemaNodeView(codeGen.sema(), codeGen.visit().currentNodeRef());
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::PointerStorageU64, reinterpret_cast<uint64_t>(resultStorage), nodeView.typeRef);
    return Result::Continue;
}

Result AstUnaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.sema().token(codeRef());
    if (tok.id != TokenId::KwdDRef)
        return Result::Continue;

    const auto* childPayload = codeGen.payload(nodeExprRef);
    if (!childPayload || childPayload->kind != CodeGenNodePayloadKind::PointerStorageU64)
        return Result::Continue;

    const auto nodeView = SemaNodeView(codeGen.sema(), codeGen.visit().currentNodeRef());
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::DerefPointerStorageU64, childPayload->valueU64, nodeView.typeRef);
    return Result::Continue;
}

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    auto&             ctx      = codeGen.ctx();
    const auto&       callConv = CallConv::host();
    MicroInstrBuilder& builder = codeGen.builder();
    const SemaNodeView exprView(codeGen.sema(), nodeExprRef);
    if (exprView.cst && exprView.type && !exprView.type->isStruct())
    {
        RESULT_VERIFY(codeGen.emitConstReturnValue(exprView));
    }
    else if (exprView.type && exprView.type->isStruct())
    {
        const uint32_t structSize = static_cast<uint32_t>(exprView.type->sizeOf(ctx));
        const auto passing = callConv.classifyStructReturnPassing(structSize);

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
