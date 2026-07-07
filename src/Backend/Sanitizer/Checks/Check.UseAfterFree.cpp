#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UseAfterFree.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void UseAfterFreeCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    if (state.freedPtrSlots.empty() || !ops)
        return;

    // Handing an already-freed pointer to a freeing callee again: double free. The
    // state is the PRE-call one, so the argument registers still carry their slots.
    if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
    {
        const Symbol* target = sanitizer.currentCallTarget();
        const auto*   fn     = target ? target->safeCast<SymbolFunction>() : nullptr;
        if (!fn)
            return;

        const uint64_t freesMask = fn->freesParamsMask();
        if (!freesMask)
            return;

        const CallConv& callConv = CallConv::get(ops[0].callConv);
        for (size_t i = 0; i < callConv.intArgRegs.size() && i < 64; i++)
        {
            if (!((freesMask >> i) & 1))
                continue;

            const SanitizerRegInfo* argInfo = sanitizer.regInfo(state, callConv.intArgRegs[i]);
            if (argInfo && argInfo->hasOriginSlot && state.freedPtrSlots.contains(argInfo->originSlot))
            {
                sanitizer.report(inst, DiagnosticId::sanity_err_double_free);
                return;
            }
        }

        return;
    }

    // Dereferencing a pointer reloaded from a freed slot. Address computations
    // ('lea') are not dereferences.
    if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
        return;
    if (inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
        return;

    const SanitizerRegInfo* baseInfo = sanitizer.regInfo(state, ops[def.memBaseOperandIndex].reg);
    if (baseInfo && baseInfo->hasOriginSlot && state.freedPtrSlots.contains(baseInfo->originSlot))
        sanitizer.report(inst, DiagnosticId::sanity_err_use_after_free);
}

SWC_END_NAMESPACE();
