#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Report/Assert.h"

// Pre-RA dead code elimination on virtual registers.
//
// Removes side-effect-free instructions whose virtual-register results are
// never consumed (transitively, across the SSA use graph). Iterates to a
// fixed point so that erasing one instruction can expose its operands as
// newly dead.
//
// An instruction is a candidate when:
//   - it is not a terminator, jump, call, or label,
//   - it does not write memory,
//   - if it defines CPU flags, it defines only virtual integer registers and
//     the flags are provably redefined before the next control-flow boundary,
//   - it defines at least one virtual register, and
//   - every defined virtual register is dead after the instruction.

SWC_BEGIN_NAMESPACE();

namespace
{
    // How many instructions write each virtual float register, counted on
    // first need. The SSA snapshot the fixed point shares keeps the values of
    // instructions erased since it was built, so the stream is read instead;
    // erasures during the fixed point only leave the counts too high.
    struct FloatDefCounts
    {
        const MicroStorage*                    storage  = nullptr;
        const MicroOperandStorage*             operands = nullptr;
        std::unordered_map<MicroReg, uint32_t> counts;
        bool                                   ready = false;

        uint32_t countFor(MicroReg reg)
        {
            if (!ready)
            {
                for (const MicroInstr& inst : storage->view())
                {
                    const MicroInstrUseDef useDef = inst.collectUseDef(*operands, nullptr);
                    for (const MicroReg def : useDef.defs)
                    {
                        if (def.isVirtualFloat())
                            ++counts[def];
                    }
                }
                ready = true;
            }

            const auto it = counts.find(reg);
            return it == counts.end() ? 0 : it->second;
        }
    };

    // A float clear zeroes the lanes that a partial write after it - cvtsi2ss,
    // cvtsd2ss - leaves alone. The use/def model reads that write as a full
    // definition, so the clear's value looks dead while the write still
    // depends on it. The clear is truly dead when the next instruction
    // replaces the whole register, or when nothing else ever writes the
    // register: a conversion folded to a constant, or merged with an equal
    // one, leaves the clear it needed behind.
    bool isUnobservedFloatClear(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstr& inst, const MicroInstrUseDef& useDef, const MicroInstrRef instRef, FloatDefCounts& floatDefs)
    {
        if (inst.op != MicroInstrOpcode::ClearReg || useDef.defs.size() != 1 || !useDef.defs[0].isVirtualFloat())
            return false;
        const MicroReg reg = useDef.defs[0];

        const MicroInstr*        next    = storage.ptr(storage.findNextInstructionRef(instRef));
        const MicroInstrOperand* nextOps = next ? next->ops(operands) : nullptr;
        if (nextOps && nextOps[0].reg == reg)
        {
            switch (next->op)
            {
                case MicroInstrOpcode::ClearReg:
                case MicroInstrOpcode::LoadRegImm:
                    return true;
                case MicroInstrOpcode::LoadRegMem:
                    if (nextOps[2].opBits == MicroOpBits::B32 || nextOps[2].opBits == MicroOpBits::B64)
                        return true;
                    break;
                case MicroInstrOpcode::LoadRegReg:
                    if (nextOps[1].reg.isAnyInt())
                        return true;
                    break;
                default:
                    break;
            }
        }

        return floatDefs.countFor(reg) == 1;
    }

    bool hasObservableSideEffect(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstr& inst, const MicroInstrUseDef& useDef, const MicroInstrRef instRef, FloatDefCounts& floatDefs)
    {
        if (useDef.isCall)
            return true;
        if (!MicroInstrInfo::hasObservableSideEffect(inst))
            return false;
        // xorps leaves the flags alone.
        if (isUnobservedFloatClear(storage, operands, inst, useDef, instRef, floatDefs))
            return false;

        // Most floating operations share generic opcodes that advertise an
        // EFLAGS definition, although their x64 encodings preserve EFLAGS.
        // Keep a float clear conservative unless the guard above proved it
        // independent: later scalar inserts can still depend on its upper
        // lanes.
        if (!MicroPassHelpers::instructionActuallyDefinesCpuFlags(inst, inst.ops(operands)))
        {
            if (inst.op == MicroInstrOpcode::ClearReg)
            {
                for (const MicroReg def : useDef.defs)
                {
                    if (def.isVirtualFloat())
                        return true;
                }
            }
            return false;
        }

        // A dead integer compute whose only side effect is the CPU flags it
        // defines is still removable when the flags are provably redefined in
        // the same straight-line window. Duplicated two-address chains that
        // value numbering rewires leave exactly this shape behind: a
        // flag-writing arithmetic prefix whose register result no longer has
        // a consumer. Other float destinations stay untouchable: a float
        // clear_reg is the upper-bits-zeroing half of a clear+partial-insert
        // idiom the use/def model reads as two independent full definitions.
        for (const MicroReg def : useDef.defs)
        {
            if (!def.isVirtualInt())
                return true;
        }

        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (inst.op == MicroInstrOpcode::Label ||
            info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
            info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
            info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
            info.flags.has(MicroInstrFlagsE::WritesMemory))
            return true;

        SWC_ASSERT(info.flags.has(MicroInstrFlagsE::DefinesCpuFlags));
        return !MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(storage, operands, instRef);
    }

    void collectDirectUseCursors(std::vector<uint8_t>& usedValues, std::vector<uint32_t>& cursors, const MicroStorage& storage, const MicroSsaState& ssaState)
    {
        SWC_ASSERT(ssaState.phis().empty());
        const auto values = ssaState.values();
        cursors.resize(values.size());
        for (uint32_t valueId = 0; valueId < values.size(); ++valueId)
        {
            const auto& uses   = values[valueId].uses;
            uint32_t&   cursor = cursors[valueId];
            cursor             = 0;
            while (cursor < uses.size() && !storage.ptr(uses[cursor].instRef))
                ++cursor;
            usedValues[valueId] = cursor < uses.size();
        }
    }

    void collectUsedValues(std::vector<uint8_t>& usedValues, std::vector<uint32_t>& worklist, const MicroStorage& storage, const MicroSsaState& ssaState)
    {
        const auto values = ssaState.values();
        usedValues.assign(values.size(), 0);
        worklist.clear();
        for (uint32_t valueId = 0; valueId < values.size(); ++valueId)
        {
            for (const auto& use : values[valueId].uses)
            {
                if (use.kind != MicroSsaState::UseSite::Kind::Instruction || !storage.ptr(use.instRef))
                    continue;
                usedValues[valueId] = 1;
                if (values[valueId].isPhi())
                    worklist.push_back(valueId);
                break;
            }
        }

        // Only instruction consumers make a phi live. Walking backwards from them
        // also handles phi cycles with no consumer, without revisiting every cycle
        // separately for every definition queried by the elimination sweep.
        while (!worklist.empty())
        {
            const uint32_t valueId = worklist.back();
            worklist.pop_back();
            const auto* phi = ssaState.phiInfoForValue(valueId);
            SWC_ASSERT(phi != nullptr);
            for (const uint32_t incomingValueId : phi->incomingValueIds)
            {
                if (incomingValueId == MicroSsaState::K_INVALID_VALUE || usedValues[incomingValueId])
                    continue;
                usedValues[incomingValueId] = 1;
                if (values[incomingValueId].isPhi())
                    worklist.push_back(incomingValueId);
            }
        }
    }

    bool allDefsAreDeadVirtualRegs(const MicroInstrUseDef& useDef, const MicroSsaState& ssaState, const std::vector<uint8_t>& usedValues, MicroInstrRef instRef)
    {
        if (useDef.defs.empty())
            return false;

        for (const MicroReg def : useDef.defs)
        {
            if (!def.isVirtual())
                return false;
            uint32_t valueId = MicroSsaState::K_INVALID_VALUE;
            if (ssaState.defValue(def, instRef, valueId) && usedValues[valueId])
                return false;
        }

        return true;
    }

    bool canEraseInstruction(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstr& inst, const MicroInstrUseDef& useDef, const MicroSsaState& ssaState, const std::vector<uint8_t>& usedValues, MicroInstrRef instRef, FloatDefCounts& floatDefs)
    {
        if (!allDefsAreDeadVirtualRegs(useDef, ssaState, usedValues, instRef))
            return false;

        return !hasObservableSideEffect(storage, operands, inst, useDef, instRef, floatDefs);
    }

    bool eliminateDeadInstructions(MicroStorage& storage, const MicroOperandStorage& operands, const MicroSsaState& ssaState, const std::vector<uint8_t>& usedValues, std::vector<uint32_t>* directUseCursors, FloatDefCounts& floatDefs)
    {
        bool       changed = false;
        const auto view    = storage.view();
        const auto endIt   = view.end();
        for (auto it = view.begin(); it != endIt;)
        {
            const MicroInstrRef instRef = it.current;
            const MicroInstr&   inst    = *it;
            ++it;

            const MicroInstrUseDef* useDef = ssaState.instrUseDef(instRef);
            if (!useDef)
                continue;

            if (!canEraseInstruction(storage, operands, inst, *useDef, ssaState, usedValues, instRef, floatDefs))
                continue;

            if (!storage.erase(instRef))
                continue;
            changed = true;

            if (!directUseCursors)
                continue;
            for (const MicroReg input : useDef->uses)
            {
                const auto reaching = ssaState.reachingDef(input, instRef);
                if (!reaching.valid())
                    continue;
                const auto& uses   = ssaState.values()[reaching.valueId].uses;
                uint32_t&   cursor = (*directUseCursors)[reaching.valueId];
                if (cursor >= uses.size() || uses[cursor].instRef != instRef)
                    continue;

                // Only deleting the current witness can change whether this
                // value is used. Skipped dead readers never become live again,
                // including repeated operands naming this same instruction.
                do
                    ++cursor;
                while (cursor < uses.size() && !storage.ptr(uses[cursor].instRef));
            }
        }

        return changed;
    }
}

Result MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    SWC_ASSERT(context.builder != nullptr);

    MicroStorage&        storage = *context.instructions;
    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
    if (!ssaState || !ssaState->isValid())
        return Result::Continue;
    // Every removable instruction defines a virtual value.
    if (ssaState->values().empty())
        return Result::Continue;

    MicroOperandStorage&  operands = *context.operands;
    std::vector<uint8_t>  usedValues;
    std::vector<uint32_t> worklist;
    bool                  changed               = false;
    bool                  directUseCursorsReady = false;
    FloatDefCounts        floatDefs;
    floatDefs.storage  = &storage;
    floatDefs.operands = &operands;

    // Erasing a dead definition cannot change the reaching value of a surviving
    // use. Keep this SSA graph for the entire fixed point and ignore erased
    // instruction consumers, instead of rebuilding CFG, dominators and SSA after
    // each level of a dead chain. Snapshot usage once per sweep to preserve the
    // original erasure order, including its CPU-flag redefinition checks.
    collectUsedValues(usedValues, worklist, storage, *ssaState);
    while (eliminateDeadInstructions(storage, operands, *ssaState, usedValues, directUseCursorsReady ? &worklist : nullptr, floatDefs))
    {
        changed = true;
        if (!ssaState->phis().empty())
            collectUsedValues(usedValues, worklist, storage, *ssaState);
        else if (!directUseCursorsReady)
        {
            // The first changed sweep already requires another collection.
            // Reuse the idle phi worklist for its first-live-reader cursors;
            // an unchanged pass pays neither allocation nor input lookups.
            collectDirectUseCursors(usedValues, worklist, storage, *ssaState);
            directUseCursorsReady = true;
        }
        else
        {
            // Publish usage only between sweeps. Flag checks still observe
            // mutations immediately, but register liveness keeps its snapshot.
            const auto values = ssaState->values();
            for (uint32_t valueId = 0; valueId < values.size(); ++valueId)
                usedValues[valueId] = worklist[valueId] < values[valueId].uses.size();
        }
    }

    if (changed)
    {
        context.passChanged = true;
        if (context.ssaState)
            context.ssaState->invalidate();
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
