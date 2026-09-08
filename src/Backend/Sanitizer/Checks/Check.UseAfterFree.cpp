#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.UseAfterFree.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // A pointer return is the only one that can carry a released address out of the
    // frame; an integer return holding one is the caller's explicit business, exactly as
    // the frame-address rule reads it.
    bool returnsPointer(Sanitizer& sanitizer, const SymbolFunction& fn)
    {
        TypeRef returnTypeRef = fn.returnTypeRef();
        if (!returnTypeRef.isValid())
            return false;

        const TypeRef unwrapped = sanitizer.ctx().typeMgr().unwrapAliasEnum(sanitizer.ctx(), returnTypeRef);
        if (unwrapped.isValid())
            returnTypeRef = unwrapped;

        const TypeInfo& returnType = sanitizer.ctx().typeMgr().get(returnTypeRef);
        return returnType.isAnyPointer() || returnType.isReference();
    }
}

void UseAfterFreeCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    // Handing a released address back to the caller is the same fault as handing back a
    // frame address, on the other kind of storage: the value is dead the moment it
    // crosses the return, and nothing the caller does with it can be right.
    if (inst.op == MicroInstrOpcode::Ret)
    {
        const SymbolFunction* fn = sanitizer.passContext().sanitizerFunction;
        if (!fn || !returnsPointer(sanitizer, *fn))
            return;

        const CallConv&         callConv   = CallConv::get(sanitizer.passContext().callConvKind);
        const SanitizerRegInfo* returnInfo = Sanitizer::regInfo(state, callConv.intReturn);
        if (!returnInfo)
            return;

        if (returnInfo->releasedPointer)
        {
            sanitizer.report(inst, DiagnosticId::sanity_err_return_released, returnInfo->releasedOrigin, DiagnosticId::sanity_note_pointer_released_here);
            return;
        }

        const auto released = returnInfo->hasPointerOriginSlot ? state.freedPtrSlots.find(returnInfo->pointerOriginSlot) : state.freedPtrSlots.end();
        if (released != state.freedPtrSlots.end())
            sanitizer.report(inst, DiagnosticId::sanity_err_return_released, released->second, DiagnosticId::sanity_note_pointer_released_here);
        return;
    }

    if (!ops)
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
            if (!argInfo)
                continue;

            // A global's address never came from the allocator: releasing it has it write
            // its own bookkeeping over storage it never handed out. The value analysis
            // proves the provenance, so no summary is needed to say it.
            if (sanitizer.getReg(state, argReg).kind == SanitizerValueKind::GlobalAddr)
            {
                sanitizer.report(inst, DiagnosticId::sanity_err_free_global);
                return;
            }

            if (argInfo->releasedPointer)
            {
                sanitizer.report(inst, DiagnosticId::sanity_err_double_free, argInfo->releasedOrigin, DiagnosticId::sanity_note_pointer_released_here);
                return;
            }

            const auto freed = argInfo->hasOriginSlot ? state.freedPtrSlots.find(argInfo->originSlot) : state.freedPtrSlots.end();
            if (freed != state.freedPtrSlots.end())
            {
                sanitizer.report(inst, DiagnosticId::sanity_err_double_free, freed->second, DiagnosticId::sanity_note_pointer_released_here);
                return;
            }

            const auto freedLocation = argInfo->hasOriginLocation ? state.freedPtrLocations.find(argInfo->originLocation) : state.freedPtrLocations.end();
            if (freedLocation != state.freedPtrLocations.end())
            {
                sanitizer.report(inst, DiagnosticId::sanity_err_double_free, freedLocation->second, DiagnosticId::sanity_note_pointer_released_here);
                return;
            }
        }

        return;
    }

    // Dereferencing a pointer reloaded from a freed slot, whatever shape the access takes.
    // Reading a FIELD of a freed object, or an ELEMENT of a freed buffer, is what a real
    // use-after-free almost always looks like, and the indexed forms carry no base+offset
    // flag: asking the table alone would answer only for a plain dereference.
    uint8_t baseOperandIndex = 0;
    if (!MicroPassHelpers::dereferenceBaseOperandIndex(baseOperandIndex, inst.op, def))
        return;

    const SanitizerRegInfo* baseInfo = Sanitizer::regInfo(state, ops[baseOperandIndex].reg);
    if (!baseInfo)
        return;

    if (baseInfo->releasedPointer)
    {
        sanitizer.report(inst, DiagnosticId::sanity_err_use_after_free, baseInfo->releasedOrigin, DiagnosticId::sanity_note_pointer_released_here);
        return;
    }

    const auto freed = baseInfo->hasPointerOriginSlot ? state.freedPtrSlots.find(baseInfo->pointerOriginSlot) : state.freedPtrSlots.end();
    if (freed != state.freedPtrSlots.end())
    {
        sanitizer.report(inst, DiagnosticId::sanity_err_use_after_free, freed->second, DiagnosticId::sanity_note_pointer_released_here);
        return;
    }

    // The pointer came out of an object rather than out of the frame: same proof, other
    // kind of storage.
    const auto freedLocation = baseInfo->hasOriginLocation ? state.freedPtrLocations.find(baseInfo->originLocation) : state.freedPtrLocations.end();
    if (freedLocation != state.freedPtrLocations.end())
        sanitizer.report(inst, DiagnosticId::sanity_err_use_after_free, freedLocation->second, DiagnosticId::sanity_note_pointer_released_here);
}

SWC_END_NAMESPACE();
