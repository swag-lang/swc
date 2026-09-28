#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenMemoryHelpers
{
    inline CodeGenNodePayload globalVariableAddressPayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        CodeGenNodePayload payload;
        payload.typeRef = symVar.typeRef();
        payload.setIsAddress();
        payload.reg = codeGen.nextVirtualIntRegister();
        emitGlobalVariableAddress(codeGen, payload.reg, symVar);
        return payload;
    }
}

SWC_END_NAMESPACE();
