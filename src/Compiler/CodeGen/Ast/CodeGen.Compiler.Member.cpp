#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
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
    const auto* leftPayload = codeGen.payload(nodeLeftRef);
    if (!leftPayload || leftPayload->kind != CodeGenNodePayloadKind::AddressValue)
        return Result::Continue;

    const SemaNodeView rightView(codeGen.sema(), nodeRightRef);
    const SymbolFunction* methodSym = resolveMethodSymbol(rightView);
    if (!methodSym)
        return Result::Continue;

    uint32_t methodSlot = 0;
    if (!tryFindInterfaceMethodSlot(methodSlot, *methodSym))
        return Result::Continue;

    const auto* runtimeInterface = reinterpret_cast<const Runtime::Interface*>(leftPayload->valueU64);
    SWC_ASSERT(runtimeInterface != nullptr);
    SWC_ASSERT(runtimeInterface->itable != nullptr);
    const auto targetAddress = reinterpret_cast<uint64_t>(runtimeInterface->itable[methodSlot]);
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::ExternalFunctionAddress, targetAddress);
    return Result::Continue;
}

SWC_END_NAMESPACE();
