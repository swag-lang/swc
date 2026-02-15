#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SymbolFunction* resolveMethodSymbol(const SemaNodeView& nodeView)
    {
        const Symbol* sym = nodeView.sym;
        if (!sym && !nodeView.symList.empty())
            sym = nodeView.symList.front();

        if (!sym || !sym->isFunction())
            return nullptr;

        return &sym->cast<SymbolFunction>();
    }

    bool tryFindInterfaceMethodSlot(uint32_t& slot, const SymbolFunction& methodSym)
    {
        slot = 0;

        const SymbolMap* ownerSymMap = methodSym.ownerSymMap();
        if (!ownerSymMap)
            return false;

        const auto* interfaceSym = ownerSymMap->safeCast<SymbolInterface>();
        if (!interfaceSym)
            return false;

        const auto& methods = interfaceSym->functions();
        for (size_t idx = 0; idx < methods.size(); idx++)
        {
            if (methods[idx] == &methodSym)
            {
                slot = static_cast<uint32_t>(idx);
                return true;
            }
        }

        return false;
    }
}

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroInstrBuilder& builder = codeGen.builder();
    const auto* leftPayload = codeGen.payload(nodeLeftRef);
    SWC_ASSERT(leftPayload != nullptr);
    SWC_ASSERT(leftPayload->kind == CodeGenNodePayloadKind::AddressValue); // TODO: replace assert with a proper codegen diagnostic.

    const auto rightView = codeGen.nodeView(nodeRightRef);
    const SymbolFunction* methodSym = resolveMethodSymbol(rightView);
    SWC_ASSERT(methodSym != nullptr);

    uint32_t methodSlot = 0;
    SWC_ASSERT(tryFindInterfaceMethodSlot(methodSlot, *methodSym)); // TODO: replace assert with a proper codegen diagnostic.

    auto& payload = codeGen.setPayload(codeGen.curNodeRef(), CodeGenNodePayloadKind::ExternalFunctionAddress, 0);
    const MicroReg leftReg = codeGen.payloadVirtualReg(*leftPayload);
    const MicroReg dstReg  = codeGen.payloadVirtualReg(payload);
    builder.encodeLoadRegMem(dstReg, leftReg, offsetof(Runtime::Interface, itable), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadRegMem(dstReg, dstReg, methodSlot * sizeof(void*), MicroOpBits::B64, EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
