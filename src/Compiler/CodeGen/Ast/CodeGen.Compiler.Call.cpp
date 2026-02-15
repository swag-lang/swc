#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_CALL_PUSH_SIZE = sizeof(void*);

    const SymbolFunction* resolveFunctionSymbol(const SemaNodeView& nodeView)
    {
        const Symbol* sym = nodeView.sym;
        if (!sym && !nodeView.symList.empty())
            sym = nodeView.symList.front();

        if (!sym || !sym->isFunction())
            return nullptr;

        return &sym->cast<SymbolFunction>();
    }

    bool isInterfaceMethod(const SymbolFunction& methodSym)
    {
        const SymbolMap* ownerSymMap = methodSym.ownerSymMap();
        if (!ownerSymMap)
            return false;
        return ownerSymMap->safeCast<SymbolInterface>() != nullptr;
    }

    uint32_t computeCallStackAdjust(const CallConv& conv, uint32_t numArgs)
    {
        const uint32_t numRegArgs    = conv.numArgRegisterSlots();
        const uint32_t stackSlotSize = conv.stackSlotSize();
        const uint32_t numStackArgs  = numArgs > numRegArgs ? numArgs - numRegArgs : 0;
        const uint32_t stackArgsSize = numStackArgs * stackSlotSize;
        const uint32_t frameBaseSize = conv.stackShadowSpace + stackArgsSize;
        const uint32_t stackAlign    = conv.stackAlignment ? conv.stackAlignment : 16;
        const uint32_t alignPad      = (stackAlign + K_CALL_PUSH_SIZE - (frameBaseSize % stackAlign)) % stackAlign;
        return frameBaseSize + alignPad;
    }
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroInstrBuilder& builder = codeGen.builder();
    const auto& callConv = CallConv::host();

    const auto* calleePayload = codeGen.payload(nodeExprRef);
    SWC_ASSERT(calleePayload != nullptr);
    SWC_ASSERT(calleePayload->kind == CodeGenNodePayloadKind::ExternalFunctionAddress); // TODO: replace assert with a proper codegen diagnostic.

    const auto& calleeNode = codeGen.node(nodeExprRef);
    SWC_ASSERT(calleeNode.id() == AstNodeId::MemberAccessExpr); // TODO: replace assert with a proper codegen diagnostic.

    const auto callView = codeGen.curNodeView();
    const SymbolFunction* calledFunction = resolveFunctionSymbol(callView);

    const AstMemberAccessExpr* memberAccessExpr = calleeNode.cast<AstMemberAccessExpr>();
    if (!calledFunction)
    {
        const auto rightView = codeGen.nodeView(memberAccessExpr->nodeRightRef);
        calledFunction = resolveFunctionSymbol(rightView);
    }

    SWC_ASSERT(calledFunction != nullptr);
    SWC_ASSERT(isInterfaceMethod(*calledFunction)); // TODO: replace assert with a proper codegen diagnostic.

    const auto* leftPayload = codeGen.payload(memberAccessExpr->nodeLeftRef);
    SWC_ASSERT(leftPayload != nullptr);
    SWC_ASSERT(leftPayload->kind == CodeGenNodePayloadKind::AddressValue); // TODO: replace assert with a proper codegen diagnostic.

    SmallVector<AstNodeRef> args;
    collectArguments(args, codeGen.ast());
    SWC_ASSERT(args.empty()); // TODO: replace assert with a proper codegen diagnostic.

    SWC_ASSERT(!callConv.intArgRegs.empty());
    const MicroReg callArg0Reg = callConv.intArgRegs[0];
    const MicroReg interfaceReg = codeGen.payloadVirtualReg(*leftPayload);
    builder.encodeLoadRegMem(callArg0Reg, interfaceReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64, EncodeFlagsE::Zero);

    const uint32_t stackAdjust = computeCallStackAdjust(callConv, 1);
    if (stackAdjust)
        builder.encodeOpBinaryRegImm(callConv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    const MicroReg calleeReg = codeGen.payloadVirtualReg(*calleePayload);
    builder.encodeCallReg(calleeReg, CallConvKind::Host, EncodeFlagsE::Zero);

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(callConv.stackPointer, stackAdjust, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);

    auto* resultStorage = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage      = 0;
    auto& nodePayload   = codeGen.setPayload(codeGen.curNodeRef(), CodeGenNodePayloadKind::PointerStorageU64, reinterpret_cast<uint64_t>(resultStorage), codeGen.curNodeView().typeRef);
    const MicroReg resultReg = codeGen.payloadVirtualReg(nodePayload);
    builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadMemReg(resultReg, 0, callConv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);

    return Result::Continue;
}

SWC_END_NAMESPACE();
