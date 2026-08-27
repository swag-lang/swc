#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UseAfterFree.h"
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

        for (size_t i = 0; i < 64; i++)
        {
            if (!((freesMask >> i) & 1))
                continue;

            MicroReg argReg;
            if (!sanitizer.callParameterRegister(argReg, *fn, ops[0].callConv, i))
                continue;
            const SanitizerRegInfo* argInfo = Sanitizer::regInfo(state, argReg);
            const auto              freed  = argInfo && argInfo->hasOriginSlot ? state.freedPtrSlots.find(argInfo->originSlot) : state.freedPtrSlots.end();
            if (freed != state.freedPtrSlots.end())
            {
                sanitizer.report(inst, DiagnosticId::sanity_err_double_free, freed->second, DiagnosticId::sanity_note_pointer_released_here);
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

    const SanitizerRegInfo* baseInfo = Sanitizer::regInfo(state, ops[def.memBaseOperandIndex].reg);
    const auto              freed    = baseInfo && baseInfo->hasOriginSlot ? state.freedPtrSlots.find(baseInfo->originSlot) : state.freedPtrSlots.end();
    if (freed != state.freedPtrSlots.end())
        sanitizer.report(inst, DiagnosticId::sanity_err_use_after_free, freed->second, DiagnosticId::sanity_note_pointer_released_here);
}

SWC_END_NAMESPACE();
