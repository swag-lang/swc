#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.StackEscape.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void StackEscapeCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef&, const MicroInstrOperand*)
{
    if (inst.op != MicroInstrOpcode::Ret)
        return;

    const SymbolFunction* fn = sanitizer.passContext().sanitizerFunction;
    if (!fn)
        return;

    // Only a pointer/reference return can carry a dangling frame address; an integer
    // return holding an address is the user's explicit (if dubious) business.
    TypeRef returnTypeRef = fn->returnTypeRef();
    if (!returnTypeRef.isValid())
        return;
    const TypeRef unwrapped = sanitizer.ctx().typeMgr().unwrapAliasEnum(sanitizer.ctx(), returnTypeRef);
    if (unwrapped.isValid())
        returnTypeRef = unwrapped;
    const TypeInfo& returnType = sanitizer.ctx().typeMgr().get(returnTypeRef);
    if (!returnType.isAnyPointer() && !returnType.isReference())
        return;

    const CallConv& callConv = CallConv::get(sanitizer.passContext().callConvKind);
    if (sanitizer.getReg(state, callConv.intReturn).isStackAddr())
        sanitizer.report(inst, DiagnosticId::sanity_err_return_local_address);
}

SWC_END_NAMESPACE();
