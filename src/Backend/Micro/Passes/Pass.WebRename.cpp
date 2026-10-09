#include "pch.h"
#include "Backend/Micro/Passes/Pass.WebRename.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct Webs
    {
        std::vector<uint32_t> parents;

        uint32_t root(uint32_t value)
        {
            while (parents[value] != value)
            {
                parents[value] = parents[parents[value]];
                value          = parents[value];
            }
            return value;
        }

        void merge(uint32_t a, uint32_t b)
        {
            a = root(a);
            b = root(b);
            if (a != b)
                parents[b] = a;
        }
    };

    // A scalar floating definition replaces its whole lane. Other widths and
    // vector operations need an upper-lane contract before their webs can split.
    bool hasScalarDoubleWidth(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::OpBinaryRegReg:
            case MicroInstrOpcode::OpBinaryRegMem:
                return ops[2].opBits == MicroOpBits::B64;
            case MicroInstrOpcode::OpBinaryRegRegReg:
                return ops[3].opBits == MicroOpBits::B64;
            default:
                return false;
        }
    }

    // Keep repeated scalar loads out of destructive floating webs. Integer
    // registers hold the unchanged bits without extending XMM interference;
    // value numbering can then share the load before the scalar copies. Only
    // a straight line without stores or address changes supplies candidates.
    // Also tells whether the function names a virtual float register at all: the renaming that
    // follows only ever splits float webs, so a function without one is left as it is.
    bool preserveRepeatedLoads(MicroPassContext& context, bool& outHasVirtualFloat)
    {
        auto& storage  = *context.instructions;
        auto& operands = *context.operands;
        // Membership only, so their order is never read; the worker keeps their buckets.
        thread_local std::unordered_set<MicroReg> destructive;
        thread_local std::unordered_set<MicroReg> excluded;
        destructive.clear();
        excluded.clear();
        outHasVirtualFloat = false;
        for (const MicroInstr& inst : storage.view())
        {
            const auto* ops = inst.ops(operands);
            if (!ops)
                continue;
            const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] == MicroInstrRegMode::None)
                    continue;
                const MicroReg reg = ops[i].reg;
                if (!reg.isVirtualFloat())
                    continue;
                outHasVirtualFloat = true;
                if (!hasScalarDoubleWidth(inst, ops) || context.builder->virtualRegForbiddenPhysRegs().contains(reg) ||
                    context.builder->shouldPreserveVirtualCopy(reg))
                    excluded.insert(reg);
                if (modes[i] == MicroInstrRegMode::UseDef)
                    destructive.insert(reg);
            }
        }
        if (destructive.empty())
            return false;

        // Value numbering deliberately leaves frame reads to mem-to-reg.
        // Preserving them here would create single-use integer copies that
        // instruction combining removes, only to recreate them next sweep.
        std::optional<std::unordered_set<MicroReg>>                                            frameDerived;
        std::unordered_map<MicroReg, std::unordered_map<uint64_t, std::vector<MicroInstrRef>>> loads;
        std::vector<MicroInstrRef>                                                             preserve;
        const auto                                                                             flush = [&] {
            for (const auto& [base, locations] : loads)
                for (const auto& [offset, refs] : locations)
                    if (refs.size() >= 2)
                        preserve.insert(preserve.end(), refs.begin(), refs.end());
            loads.clear();
        };
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const auto& info = MicroInstr::info(it->op);
            const auto* ops  = it->ops(operands);
            if (it->op == MicroInstrOpcode::Label || it->op == MicroInstrOpcode::LoadVolatileRegMem || info.flags.has(MicroInstrFlagsE::WritesMemory) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
            {
                flush();
                continue;
            }
            const auto modes = info.resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if ((modes[i] == MicroInstrRegMode::Def || modes[i] == MicroInstrRegMode::UseDef) && ops[i].reg.isAnyInt())
                {
                    flush();
                    break;
                }
            }
            if (it->op == MicroInstrOpcode::LoadRegMem && ops[2].opBits == MicroOpBits::B64 &&
                ops[0].reg.isVirtualFloat() && ops[1].reg.isVirtualInt() &&
                destructive.contains(ops[0].reg) && !excluded.contains(ops[0].reg))
            {
                if (!frameDerived)
                    MicroPassHelpers::collectFrameDerivedRegs(frameDerived.emplace(), storage, operands, CallConv::get(context.callConvKind).stackPointer);
                if (!frameDerived->contains(ops[1].reg))
                    loads[ops[1].reg][ops[3].valueU64].push_back(it.current);
            }
        }
        flush();
        if (preserve.empty())
            return false;
        uint32_t nextInt = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        if (preserve.size() >= MicroReg::K_MAX_INDEX - nextInt)
            return false;
        for (const auto ref : preserve)
        {
            auto*          ops      = storage.ptr(ref)->ops(operands);
            const MicroReg original = ops[0].reg;
            const MicroReg cached   = MicroReg::virtualIntReg(nextInt++);
            ops[0].reg              = cached;
            MicroInstrOperand copy[3];
            copy[0].reg    = original;
            copy[1].reg    = cached;
            copy[2].opBits = MicroOpBits::B64;
            storage.insertDerivedBefore(operands, storage.findNextInstructionRef(ref), MicroInstrOpcode::LoadRegReg, copy);
        }
        return true;
    }
}

Result MicroWebRenamePass::run(MicroPassContext& context)
{
    if (!context.builder || !context.instructions || !context.operands)
        return Result::Continue;

    bool hasVirtualFloat = false;
    if (preserveRepeatedLoads(context, hasVirtualFloat))
    {
        context.passChanged = true;
        return Result::Continue;
    }

    // A candidate is the stored source of a float store, so without a virtual float register
    // there is none: the SSA state and the scan below would find nothing.
    if (!hasVirtualFloat)
        return Result::Continue;

    std::optional<MicroSsaState> local;
    MicroSsaState&               scratch = context.ssaState ? *context.ssaState : local.emplace();
    const auto*                  ssa     = MicroSsaState::ensureFor(context, scratch);
    if (!ssa)
        return Result::Continue;

    // Split names only when their reuse hides a stored value from a later
    // load of the same location. Splitting every arithmetic temporary can
    // lengthen unrelated live ranges without exposing memory forwarding.
    struct StoredValue
    {
        MicroReg source;
        uint32_t value;
    };
    std::unordered_map<MicroReg, std::unordered_map<uint64_t, StoredValue>> storedValues;
    std::unordered_set<MicroReg>                                            candidates;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        const auto flags = MicroInstr::info(it->op).flags;
        if (it->op == MicroInstrOpcode::Label || flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::IsCallInstruction))
        {
            storedValues.clear();
            continue;
        }
        const auto* ops = it->ops(*context.operands);
        if (it->op == MicroInstrOpcode::LoadMemReg && ops[2].opBits == MicroOpBits::B64 && ops[1].reg.isVirtualFloat())
        {
            const uint32_t valueId = ssa->reachingValueId(ops[1].reg, it.current);
            if (valueId != MicroSsaState::K_INVALID_VALUE)
                storedValues[ops[0].reg].insert_or_assign(ops[3].valueU64, StoredValue{ops[1].reg, valueId});
        }
        else if ((it->op == MicroInstrOpcode::LoadRegMem || it->op == MicroInstrOpcode::OpBinaryRegMem) && ops[2].opBits == MicroOpBits::B64)
        {
            const uint64_t offset = ops[it->op == MicroInstrOpcode::LoadRegMem ? 3 : 4].valueU64;
            const auto     base   = storedValues.find(ops[1].reg);
            if (base == storedValues.end())
                continue;
            const auto stored = base->second.find(offset);
            if (stored != base->second.end() && ssa->reachingValueId(stored->second.source, it.current) != stored->second.value)
                candidates.insert(stored->second.source);
        }
    }
    if (candidates.empty())
        return Result::Continue;

    const auto values = ssa->values();
    Webs       webs;
    webs.parents.resize(values.size());
    std::iota(webs.parents.begin(), webs.parents.end(), 0u);
    std::unordered_set<MicroReg> excluded;
    for (const auto& phi : ssa->phis())
    {
        // A web only connects versions of its own register. Other registers
        // cannot affect the names of the stored-value candidates.
        if (!phi.reg.isVirtualFloat() || !candidates.contains(phi.reg) || !ssa->transitiveInstructionUseCount(phi.resultValueId, 1))
            continue;
        for (const uint32_t incoming : phi.incomingValueIds)
        {
            if (incoming == MicroSsaState::K_INVALID_VALUE)
                excluded.insert(phi.reg);
            else
                webs.merge(phi.resultValueId, incoming);
        }
    }

    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        const auto* ops = it->ops(*context.operands);
        if (!ops)
            continue;
        const auto modes = MicroInstr::info(it->op).resolvedRegModes(ops);
        for (size_t operand = 0; operand < modes.size(); ++operand)
        {
            if (modes[operand] == MicroInstrRegMode::None || !ops[operand].reg.isVirtualFloat() || !candidates.contains(ops[operand].reg))
                continue;
            const MicroReg reg = ops[operand].reg;
            if (!hasScalarDoubleWidth(*it, ops))
            {
                excluded.insert(reg);
                continue;
            }
            if (context.builder->virtualRegForbiddenPhysRegs().contains(reg) || context.builder->shouldPreserveVirtualCopy(reg))
            {
                excluded.insert(reg);
                continue;
            }
            uint32_t inputValue = MicroSsaState::K_INVALID_VALUE;
            if (modes[operand] == MicroInstrRegMode::Use || modes[operand] == MicroInstrRegMode::UseDef)
            {
                inputValue = ssa->reachingValueId(reg, it.current);
                if (inputValue == MicroSsaState::K_INVALID_VALUE)
                    excluded.insert(reg);
            }
            if (modes[operand] == MicroInstrRegMode::Def || modes[operand] == MicroInstrRegMode::UseDef)
            {
                uint32_t definition;
                if (!ssa->defValue(reg, it.current, definition))
                {
                    excluded.insert(reg);
                    continue;
                }
                if (modes[operand] == MicroInstrRegMode::UseDef && inputValue != MicroSsaState::K_INVALID_VALUE)
                    webs.merge(definition, inputValue);
            }
        }
    }

    uint32_t                               nextFloat = 0;
    std::unordered_set<MicroReg>           namedRegs;
    std::unordered_map<uint32_t, MicroReg> names;
    for (uint32_t id = 0; id < values.size(); ++id)
    {
        const auto& value = values[id];
        if (!candidates.contains(value.reg) || excluded.contains(value.reg) || value.isPhi())
            continue;
        const uint32_t web          = webs.root(id);
        const auto [name, inserted] = names.try_emplace(web, value.reg);
        if (!inserted)
            continue;
        if (!namedRegs.insert(value.reg).second)
        {
            if (!nextFloat)
                nextFloat = MicroPassHelpers::computeNextVirtualFloatRegIndex(context);
            if (nextFloat >= MicroReg::K_MAX_INDEX)
                return Result::Continue;
            name->second = MicroReg::virtualFloatReg(nextFloat++);
        }
    }

    // With one web per candidate, every name is still the original register.
    if (!nextFloat)
        return Result::Continue;

    struct Rewrite
    {
        MicroInstrOperand* operand;
        MicroReg           reg;
    };
    std::vector<Rewrite> rewrites;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        auto* ops = it->ops(*context.operands);
        if (!ops)
            continue;
        const auto modes = MicroInstr::info(it->op).resolvedRegModes(ops);
        for (size_t operand = 0; operand < modes.size(); ++operand)
        {
            if (modes[operand] == MicroInstrRegMode::None)
                continue;
            const MicroReg reg = ops[operand].reg;
            if (!candidates.contains(reg) || excluded.contains(reg))
                continue;
            uint32_t id = MicroSsaState::K_INVALID_VALUE;
            if (modes[operand] == MicroInstrRegMode::Def || modes[operand] == MicroInstrRegMode::UseDef)
                ssa->defValue(reg, it.current, id);
            else
                id = ssa->reachingValueId(reg, it.current);
            if (id == MicroSsaState::K_INVALID_VALUE)
                continue;
            const auto name = names.find(webs.root(id));
            if (name != names.end() && name->second != reg)
                rewrites.push_back({&ops[operand], name->second});
        }
    }
    for (const auto& rewrite : rewrites)
        rewrite.operand->reg = rewrite.reg;
    context.passChanged = !rewrites.empty();
    return Result::Continue;
}

SWC_END_NAMESPACE();
