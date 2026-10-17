#include "pch.h"
#include "Backend/Micro/Passes/Pass.StoreForwardSplit.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID = MicroSsaState::K_INVALID_VALUE;
    // The frame the stack pointer addresses has no SSA value of its own.
    constexpr uint32_t K_STACK_OBJECT = K_INVALID - 1;
    constexpr int64_t  K_WIDE_BYTES   = 16;
    constexpr int64_t  K_HALF_BYTES   = 8;

    // Where an access points: an object named by the value its address starts from,
    // a constant offset into it, and the bytes a loop adds to that address per trip.
    struct Address
    {
        uint32_t object = K_INVALID;
        int64_t  offset = 0;
        int64_t  stride = 0;
    };

    struct Access
    {
        MicroInstrRef ref;
        Address       address;
        int64_t       size     = 0;
        uint32_t      cfgIndex = 0;
    };

    class AddressResolver
    {
    public:
        AddressResolver(const MicroPassContext& context, const MicroSsaState& ssa) :
            ssa_(&ssa),
            storage_(context.instructions),
            operands_(context.operands),
            stackPointer_(context.encoder->stackPointerReg())
        {
        }

        bool resolve(Address& out, MicroReg reg, MicroInstrRef at) const
        {
            out = {};
            if (reg == stackPointer_)
            {
                out.object = K_STACK_OBJECT;
                return true;
            }
            if (!reg.isVirtualInt())
                return false;

            uint32_t value = ssa_->reachingValueId(reg, at);
            for (uint32_t depth = 0; depth < MicroPassHelpers::K_MAX_ROOT_CHAIN && value != K_INVALID; ++depth)
            {
                const MicroSsaState::ValueInfo* info = ssa_->valueInfo(value);
                if (info->isPhi())
                {
                    int64_t        stride  = 0;
                    const uint32_t initial = out.stride ? K_INVALID : steppedInitialValue(stride, value);
                    if (initial == K_INVALID)
                    {
                        out.object = value;
                        return true;
                    }
                    out.stride = stride;
                    value      = initial;
                    continue;
                }

                const MicroInstr&        inst   = *storage_->ptr(info->instRef);
                const MicroInstrOperand* ops    = inst.ops(*operands_);
                MicroReg                 source = MicroReg::invalid();
                int64_t                  step   = 0;
                if (inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[2].opBits == MicroOpBits::B64)
                {
                    source = ops[1].reg;
                    step   = static_cast<int64_t>(ops[3].valueU64);
                }
                else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[2].opBits == MicroOpBits::B64)
                {
                    source = ops[1].reg;
                }
                else if (!addedImmediate(step, inst, ops))
                {
                    out.object = value;
                    return true;
                }
                else
                {
                    source = ops[0].reg;
                }

                out.offset += step;
                if (source == stackPointer_)
                {
                    out.object = K_STACK_OBJECT;
                    return true;
                }
                if (!source.isVirtualInt())
                {
                    out.object = value;
                    return true;
                }
                value = ssa_->reachingValueId(source, info->instRef);
            }
            return false;
        }

    private:
        static bool addedImmediate(int64_t& outStep, const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegImm || ops[1].opBits != MicroOpBits::B64)
                return false;
            if (ops[2].microOp != MicroOp::Add && ops[2].microOp != MicroOp::Subtract)
                return false;
            const auto imm = static_cast<int64_t>(ops[3].valueU64);
            outStep        = ops[2].microOp == MicroOp::Add ? imm : -imm;
            return true;
        }

        // A loop steps a pointer when the phi joining it has two inputs, one of them the
        // phi plus a constant. Returns the other input, the pointer the loop starts from.
        uint32_t steppedInitialValue(int64_t& outStride, uint32_t phiValue) const
        {
            const MicroSsaState::PhiInfo* phi = ssa_->phiInfoForValue(phiValue);
            if (!phi || phi->incomingValueIds.size() != 2)
                return K_INVALID;
            for (uint32_t index = 0; index < 2; ++index)
            {
                const MicroSsaState::ValueInfo* step = ssa_->valueInfo(phi->incomingValueIds[index]);
                if (!step || step->isPhi())
                    continue;
                const MicroInstr&        inst = *storage_->ptr(step->instRef);
                const MicroInstrOperand* ops  = inst.ops(*operands_);
                int64_t                  stride;
                if (!addedImmediate(stride, inst, ops) || !stride || ssa_->reachingValueId(ops[0].reg, step->instRef) != phiValue)
                    continue;
                outStride = stride;
                return phi->incomingValueIds[1 - index];
            }
            return K_INVALID;
        }

        const MicroSsaState*       ssa_;
        const MicroStorage*        storage_;
        const MicroOperandStorage* operands_;
        MicroReg                   stackPointer_;
    };

    // The plain stores: one base register, a constant offset, no index.
    bool isPlainStore(MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::LoadMemImm:
            case MicroInstrOpcode::StoreVecMemReg:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
                return true;
            default:
                return false;
        }
    }

    // How a store's bytes sit against a range of the load, for every trip of the loops
    // that step either address: whether some trip makes them meet, and whether every
    // trip that does covers the range whole.
    struct Overlap
    {
        bool meets  = false;
        bool covers = true;
    };

    // `delta` is where the store starts relative to the range, `period` the step both
    // addresses can drift apart by (zero when neither moves).
    Overlap overlapOf(int64_t delta, int64_t storeSize, int64_t rangeSize, int64_t period)
    {
        Overlap    result;
        const auto add = [&](int64_t start) {
            if (start >= rangeSize || start + storeSize <= 0)
                return;
            result.meets = true;
            result.covers &= start <= 0 && start + storeSize >= rangeSize;
        };
        if (!period)
        {
            add(delta);
            return result;
        }
        const int64_t first = ((delta % period) + period) % period;
        add(first);
        add(first - period);
        return result;
    }

    struct SplitPlan
    {
        std::vector<Access>                     stores;
        const MicroPassHelpers::NaturalLoopMap* loops = nullptr;

        // A store delays the load when both run on one trip of a loop, or when it
        // precedes a load no loop repeats.
        bool sameTrip(uint32_t loadIndex, uint32_t storeIndex) const
        {
            bool loadInLoop = false;
            if (loops)
            {
                for (const auto& [header, loop] : *loops)
                {
                    if (!loop.inBody[loadIndex])
                        continue;
                    if (loop.inBody[storeIndex])
                        return true;
                    loadInLoop = true;
                }
            }
            return !loadInLoop && storeIndex < loadIndex;
        }

        bool shouldSplit(const Access& load) const
        {
            bool blocked = false;
            for (const Access& store : stores)
            {
                if (store.address.object != load.address.object)
                    continue;
                const int64_t period = std::gcd(load.address.stride, store.address.stride);
                // Addresses that drift by less than two loads can meet in ways a split cannot fix.
                if (period && period < 2 * K_WIDE_BYTES)
                    return false;
                const int64_t delta = store.address.offset - load.address.offset;
                const Overlap whole = overlapOf(delta, store.size, K_WIDE_BYTES, period);
                if (!whole.meets || whole.covers || !sameTrip(load.cfgIndex, store.cfgIndex))
                    continue;
                // Each half must be covered by one store, or not touched at all.
                for (int64_t half = 0; half < K_WIDE_BYTES; half += K_HALF_BYTES)
                {
                    const Overlap part = overlapOf(delta - half, store.size, K_HALF_BYTES, period);
                    if (part.meets && !part.covers)
                        return false;
                }
                blocked = true;
            }
            return blocked;
        }
    };

    bool decodeAccess(Access& out, const AddressResolver& resolver, const MicroInstr& inst, const MicroInstrOperand* ops, MicroInstrRef ref)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        out.ref                   = ref;
        out.size                  = getNumBytes(ops[std::countr_zero(static_cast<uint32_t>(info.opBitsMask))].opBits);
        if (!resolver.resolve(out.address, ops[info.memBaseOperandIndex].reg, ref))
            return false;
        out.address.offset += static_cast<int64_t>(ops[info.memOffsetOperandIndex].valueU64);
        return true;
    }
}

Result MicroStoreForwardSplitPass::run(MicroPassContext& context)
{
    if (!context.builder || !context.instructions || !context.operands || !context.encoder)
        return Result::Continue;
    if (!context.builder->backendBuildCfg().optimizes())
        return Result::Continue;

    SmallVector<MicroInstrRef, 8> wideLoads;
    for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
    {
        if (it->op == MicroInstrOpcode::LoadVecRegMem && it->ops(*context.operands)[1].reg.isVirtualInt())
            wideLoads.push_back(it.current);
    }
    if (wideLoads.empty())
        return Result::Continue;

    MicroSsaState        localSsa;
    const MicroSsaState* ssa = MicroSsaState::ensureFor(context, localSsa);
    if (!ssa)
        return Result::Continue;

    const MicroControlFlowGraph&   cfg = context.builder->controlFlowGraph();
    const AddressResolver          resolver(context, *ssa);
    SplitPlan                      plan;
    MicroPassHelpers::MicroDomTree dom;
    if (cfg.hasLoop())
    {
        const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
        if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
            return Result::Continue;
        dom        = MicroPassHelpers::computeInstructionDominators(cfg, entry, ssa);
        plan.loops = &MicroPassHelpers::naturalLoopsFor(context.ssaState, cfg, dom);
    }

    for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
    {
        if (!isPlainStore(it->op))
            continue;
        Access store;
        if (!decodeAccess(store, resolver, *it, it->ops(*context.operands), it.current))
            continue;
        store.cfgIndex = cfg.indexOf(it.current);
        plan.stores.push_back(store);
    }
    if (plan.stores.empty())
        return Result::Continue;

    SmallVector<MicroInstrRef, 8> splits;
    for (const MicroInstrRef ref : wideLoads)
    {
        const MicroInstr& inst = *context.instructions->ptr(ref);
        Access            load;
        if (!decodeAccess(load, resolver, inst, inst.ops(*context.operands), ref) || load.size != K_WIDE_BYTES)
            continue;
        load.cfgIndex = cfg.indexOf(ref);
        if (plan.shouldSplit(load))
            splits.push_back(ref);
    }
    if (splits.empty())
        return Result::Continue;

    uint32_t nextIntIndex   = 0;
    uint32_t nextFloatIndex = 0;
    MicroPassHelpers::computeNextVirtualRegIndices(context, nextIntIndex, nextFloatIndex);
    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    for (const MicroInstrRef ref : splits)
    {
        const MicroInstrOperand* loadOps   = storage.ptr(ref)->ops(operands);
        const MicroReg           dst       = loadOps[0].reg;
        const MicroReg           base      = loadOps[1].reg;
        const uint64_t           offset    = loadOps[3].valueU64;
        const MicroReg           halves[2] = {MicroReg::virtualFloatReg(nextFloatIndex++), MicroReg::virtualFloatReg(nextFloatIndex++)};
        for (uint32_t half = 0; half < 2; ++half)
        {
            std::array<MicroInstrOperand, 4> ops;
            ops[0].reg      = halves[half];
            ops[1].reg      = base;
            ops[2].opBits   = MicroOpBits::B64;
            ops[3].valueU64 = offset + half * K_HALF_BYTES;
            storage.insertDerivedBefore(operands, ref, MicroInstrOpcode::LoadRegMem, ops);
        }
        std::array<MicroInstrOperand, 5> join;
        join[0].reg     = dst;
        join[1].reg     = halves[0];
        join[2].reg     = halves[1];
        join[3].opBits  = MicroOpBits::B128;
        join[4].microOp = MicroOp::VecUnpackLo64;
        storage.insertDerivedBefore(operands, ref, MicroInstrOpcode::OpBinaryRegRegReg, join);
        storage.erase(ref);
    }

    context.passChanged = true;
    context.builder->invalidateControlFlowGraph();
    return Result::Continue;
}

SWC_END_NAMESPACE();
