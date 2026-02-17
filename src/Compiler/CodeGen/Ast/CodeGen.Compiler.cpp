#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/ABI/ABICall.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstCompilerRunExpr::codeGenPreNode(CodeGen& codeGen)
{
    const auto& callConv = CallConv::host();
    SWC_ASSERT(!callConv.intArgRegs.empty());

    const MicroReg outputStorageReg = callConv.intArgRegs[0];
    auto&          nodePayload      = codeGen.setPayload(codeGen.curNodeRef());
    codeGen.builder().encodeLoadRegReg(nodePayload.reg, outputStorageReg, MicroOpBits::B64);
    nodePayload.storageKind = CodeGenNodePayload::StorageKind::Address;
    return Result::Continue;
}

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    auto&              ctx          = codeGen.ctx();
    const auto&        callConv     = CallConv::host();
    constexpr auto     callConvKind = CallConvKind::Host;
    MicroInstrBuilder& builder      = codeGen.builder();
    const auto         exprView     = codeGen.nodeView(nodeExprRef);
    SWC_ASSERT(exprView.type);

    const auto* payload = codeGen.payload(nodeExprRef);
    SWC_ASSERT(payload != nullptr);
    const MicroReg payloadReg       = payload->reg;
    const bool     payloadLValue    = payload->storageKind == CodeGenNodePayload::StorageKind::Address;
    const auto*    runExprPayload   = codeGen.payload(codeGen.curNodeRef());
    const MicroReg outputStorageReg = runExprPayload ? runExprPayload->reg : MicroReg::invalid();
    SWC_ASSERT(outputStorageReg.isValid());

    const auto normalizedRet = ABITypeNormalize::normalize(ctx, callConv, exprView.typeRef, ABITypeNormalize::Usage::Return);

    if (normalizedRet.isIndirect)
    {
        SWC_ASSERT(normalizedRet.indirectSize != 0);
        if (payload->storageKind == CodeGenNodePayload::StorageKind::Address)
        {
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, payloadReg, normalizedRet.indirectSize);
        }
        else
        {
            const auto spillSize = normalizedRet.indirectSize;
            auto*      spillData = codeGen.ctx().compiler().allocateArray<std::byte>(spillSize);
            std::memset(spillData, 0, spillSize);

            const MicroReg spillAddrReg = codeGen.nextVirtualIntRegister();

            builder.encodeLoadRegImm(spillAddrReg, reinterpret_cast<uint64_t>(spillData), MicroOpBits::B64);
            builder.encodeLoadMemReg(spillAddrReg, 0, payloadReg, MicroOpBits::B64);
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, spillAddrReg, spillSize);
        }
    }
    else
    {
        ABICall::storeValueToReturnBuffer(builder, callConvKind, outputStorageReg, payloadReg, payloadLValue, normalizedRet);
    }
    builder.encodeRet();
    return Result::Continue;
}

Result AstIntrinsicCall::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
        {
            SmallVector<AstNodeRef> children;
            codeGen.ast().appendNodes(children, spanChildrenRef);
            SWC_ASSERT(!children.empty());

            const AstNodeRef exprRef     = children[0];
            const auto*      exprPayload = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
            const auto       exprView    = codeGen.nodeView(exprRef);
            auto&            payload     = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
            auto&            builder     = codeGen.builder();

            if (exprView.type && (exprView.type->isString() || exprView.type->isSlice() || exprView.type->isAny()))
            {
                builder.encodeLoadRegMem(payload.reg, exprPayload->reg, 0, MicroOpBits::B64);
            }
            else if (exprView.type && exprView.type->isArray())
            {
                builder.encodeLoadRegReg(payload.reg, exprPayload->reg, MicroOpBits::B64);
            }
            else if (exprPayload->storageKind == CodeGenNodePayload::StorageKind::Address)
            {
                builder.encodeLoadRegMem(payload.reg, exprPayload->reg, 0, MicroOpBits::B64);
            }
            else
            {
                builder.encodeLoadRegReg(payload.reg, exprPayload->reg, MicroOpBits::B64);
            }

            payload.storageKind = CodeGenNodePayload::StorageKind::Value;
            return Result::Continue;
        }

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
