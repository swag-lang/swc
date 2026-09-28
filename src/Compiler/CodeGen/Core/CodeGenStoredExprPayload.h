#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenStoredExprPayload
{
    // Count-of checks caller-return storage; foreach uses the other stored-symbol cases only.
    enum class CallerReturnStorageE
    {
        Exclude,
        Include,
    };

    template<CallerReturnStorageE CALLER_RETURN_STORAGE>
    inline CodeGenNodePayload resolve(CodeGen& codeGen, AstNodeRef exprRef)
    {
        if (const auto* payload = codeGen.safePayload(exprRef))
        {
            if (payload->reg.isValid())
                return *payload;
        }

        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (storedView.sym() && storedView.sym()->isVariable())
        {
            const auto& symVar = storedView.sym()->cast<SymbolVariable>();
            if (symVar.isClosureCapture() ||
                (CALLER_RETURN_STORAGE == CallerReturnStorageE::Include && CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar)) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) ||
                symVar.hasGlobalStorage() ||
                codeGen.variablePayload(symVar) ||
                (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
                return CodeGenFunctionHelpers::resolveStoredVariablePayload(codeGen, symVar);
        }

        return codeGen.payload(exprRef);
    }
}

SWC_END_NAMESPACE();
