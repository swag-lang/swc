#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
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

    const SymbolFunction* resolveCalledFunction(CodeGen& codeGen, AstNodeRef calleeRef)
    {
        const auto callView = codeGen.curNodeView();
        if (const auto fromCall = resolveFunctionSymbol(callView))
            return fromCall;

        const auto calleeView = codeGen.nodeView(calleeRef);
        return resolveFunctionSymbol(calleeView);
    }

    AstNodeRef resolveCalleeRef(CodeGen& codeGen, AstNodeRef calleeRef)
    {
        AstNodeRef currentRef = calleeRef;
        for (uint32_t i = 0; i < 16 && currentRef.isValid(); ++i)
        {
            const AstNodeRef substituteRef = codeGen.sema().getSubstituteRef(currentRef);
            if (substituteRef.isValid() && substituteRef != currentRef)
            {
                currentRef = substituteRef;
                continue;
            }

            const AstNode& node = codeGen.node(currentRef);
            if (node.id() == AstNodeId::MemberAccessExpr)
                return currentRef;

            SmallVector<AstNodeRef> children;
            Ast::nodeIdInfos(node.id()).collectChildren(children, codeGen.ast(), node);
            if (children.size() != 1 || !children.front().isValid())
                break;

            currentRef = children.front();
        }

        return currentRef;
    }

    bool tryResolveInterfaceReceiver(CodeGen& codeGen, AstNodeRef calleeRef, const SymbolFunction* calledFunction, AstNodeRef& outReceiverRef)
    {
        outReceiverRef = AstNodeRef::invalid();
        if (!calledFunction || !isInterfaceMethod(*calledFunction))
            return false;

        const AstMemberAccessExpr* memberAccessExpr = codeGen.node(calleeRef).safeCast<AstMemberAccessExpr>();
        if (!memberAccessExpr)
            return false;

        const auto leftView = codeGen.nodeView(memberAccessExpr->nodeLeftRef);
        if (!leftView.type || !leftView.type->isInterface())
            return false;

        outReceiverRef = memberAccessExpr->nodeLeftRef;
        return true;
    }

    const CodeGenNodePayload* resolveCalleePayload(CodeGen& codeGen, AstNodeRef calleeRef)
    {
        AstNodeRef currentRef = resolveCalleeRef(codeGen, calleeRef);
        for (uint32_t i = 0; i < 16 && currentRef.isValid(); ++i)
        {
            if (const auto* payload = codeGen.payload(currentRef))
                return payload;

            const AstNodeRef substituteRef = codeGen.sema().getSubstituteRef(currentRef);
            if (substituteRef.isValid() && substituteRef != currentRef)
            {
                currentRef = substituteRef;
                continue;
            }

            const AstNode& node = codeGen.node(currentRef);
            SmallVector<AstNodeRef> children;
            Ast::nodeIdInfos(node.id()).collectChildren(children, codeGen.ast(), node);
            if (children.size() != 1 || !children.front().isValid())
                break;

            currentRef = children.front();
        }

        return nullptr;
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
    const auto&        callConv = CallConv::host();

    const AstNodeRef resolvedCalleeRef = resolveCalleeRef(codeGen, nodeExprRef);
    const auto*      calleePayload     = resolveCalleePayload(codeGen, resolvedCalleeRef);
    SWC_ASSERT(calleePayload != nullptr);

    const SymbolFunction* calledFunction = resolveCalledFunction(codeGen, resolvedCalleeRef);

    SmallVector<AstNodeRef> args;
    collectArguments(args, codeGen.ast());
    SWC_ASSERT(args.empty()); // TODO: replace assert with a proper codegen diagnostic.

    uint32_t numAbiArgs = 0;
    AstNodeRef interfaceReceiverRef = AstNodeRef::invalid();
    if (tryResolveInterfaceReceiver(codeGen, resolvedCalleeRef, calledFunction, interfaceReceiverRef))
    {
        SWC_ASSERT(!callConv.intArgRegs.empty());
        const auto* receiverPayload = codeGen.payload(interfaceReceiverRef);
        SWC_ASSERT(receiverPayload != nullptr);

        const MicroReg callArg0Reg  = callConv.intArgRegs[0];
        const MicroReg interfaceReg = codeGen.payloadVirtualReg(*receiverPayload);
        builder.encodeLoadRegMem(callArg0Reg, interfaceReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64, EncodeFlagsE::Zero);
        numAbiArgs = 1;
    }

    const uint32_t stackAdjust = computeCallStackAdjust(callConv, numAbiArgs);
    if (stackAdjust)
        builder.encodeOpBinaryRegImm(callConv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    const MicroReg calleeReg = codeGen.payloadVirtualReg(*calleePayload);
    builder.encodeCallReg(calleeReg, CallConvKind::Host, EncodeFlagsE::Zero);

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(callConv.stackPointer, stackAdjust, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);

    auto* resultStorage = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage      = 0;
    auto& nodePayload   = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
    const MicroReg resultReg = codeGen.payloadVirtualReg(nodePayload);
    builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadMemReg(resultReg, 0, callConv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);

    return Result::Continue;
}

SWC_END_NAMESPACE();
