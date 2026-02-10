#include "pch.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/TypedStore.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct RegUseDef
    {
        SmallVector<MicroReg, 6> uses;
        SmallVector<MicroReg, 3> defs;
        bool                     isCall   = false;
        CallConvKind             callConv = CallConvKind::C;
    };

    struct RegOperandRef
    {
        MicroReg* reg = nullptr;
        bool      use = false;
        bool      def = false;
    };

    void addUse(RegUseDef& info, MicroReg reg)
    {
        if (reg.isValid() && !reg.isNoBase())
            info.uses.push_back(reg);
    }

    void addDef(RegUseDef& info, MicroReg reg)
    {
        if (reg.isValid() && !reg.isNoBase())
            info.defs.push_back(reg);
    }

    void addUseDef(RegUseDef& info, MicroReg reg)
    {
        addUse(info, reg);
        addDef(info, reg);
    }

    void addOperand(SmallVector<RegOperandRef, 8>& out, MicroReg* reg, bool use, bool def)
    {
        if (!reg || !reg->isValid() || reg->isNoBase())
            return;
        out.push_back({reg, use, def});
    }

    RegUseDef collectRegUseDef(const MicroInstr& inst, const Store& store)
    {
        RegUseDef info;
        auto*     ops = inst.ops(store);
        switch (inst.op)
        {
            case MicroInstrOpcode::End:
            case MicroInstrOpcode::Enter:
            case MicroInstrOpcode::Leave:
            case MicroInstrOpcode::Ignore:
            case MicroInstrOpcode::Label:
            case MicroInstrOpcode::Debug:
            case MicroInstrOpcode::LoadCallParam:
            case MicroInstrOpcode::LoadCallAddrParam:
            case MicroInstrOpcode::LoadCallZeroExtParam:
            case MicroInstrOpcode::StoreCallParam:
            case MicroInstrOpcode::Nop:
            case MicroInstrOpcode::Ret:
                break;

            case MicroInstrOpcode::SymbolRelocAddr:
            case MicroInstrOpcode::SymbolRelocValue:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::SetCondReg:
            case MicroInstrOpcode::ClearReg:
                addDef(info, ops[0].reg);
                break;

            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::CmpRegImm:
                addUse(info, ops[0].reg);
                break;

            case MicroInstrOpcode::Pop:
                addDef(info, ops[0].reg);
                break;

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                info.isCall   = true;
                info.callConv = ops[1].callConv;
                break;

            case MicroInstrOpcode::CallIndirect:
                info.isCall   = true;
                info.callConv = ops[1].callConv;
                addUse(info, ops[0].reg);
                break;

            case MicroInstrOpcode::JumpTable:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            case MicroInstrOpcode::PatchJump:
                break;

            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadCondRegReg:
                addDef(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                addDef(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                addDef(info, ops[0].reg);
                addUse(info, ops[1].reg);
                addUse(info, ops[2].reg);
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                addUse(info, ops[2].reg);
                break;

            case MicroInstrOpcode::LoadAmcMemImm:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::LoadMemReg:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::LoadMemImm:
                addUse(info, ops[0].reg);
                break;

            case MicroInstrOpcode::CmpRegReg:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::CmpMemReg:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::CmpMemImm:
                addUse(info, ops[0].reg);
                break;

            case MicroInstrOpcode::OpUnaryMem:
                addUse(info, ops[0].reg);
                break;

            case MicroInstrOpcode::OpUnaryReg:
                addUseDef(info, ops[0].reg);
                break;

            case MicroInstrOpcode::OpBinaryRegReg:
            {
                const auto op = ops[3].microOp;
                if (op == MicroOp::Exchange)
                {
                    addUseDef(info, ops[0].reg);
                    addUseDef(info, ops[1].reg);
                }
                else
                {
                    addUseDef(info, ops[0].reg);
                    addUse(info, ops[1].reg);
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryRegImm:
                addUseDef(info, ops[0].reg);
                break;

            case MicroInstrOpcode::OpBinaryRegMem:
                addUseDef(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::OpBinaryMemReg:
            {
                const auto op = ops[3].microOp;
                addUse(info, ops[0].reg);
                if (op == MicroOp::Exchange)
                    addUseDef(info, ops[1].reg);
                else
                    addUse(info, ops[1].reg);
                break;
            }
            case MicroInstrOpcode::OpBinaryMemImm:
                addUse(info, ops[0].reg);
                break;

            case MicroInstrOpcode::OpTernaryRegRegReg:
            {
                const auto op = ops[4].microOp;
                if (op == MicroOp::CompareExchange)
                {
                    addUseDef(info, ops[0].reg);
                    addUseDef(info, ops[1].reg);
                    addUse(info, ops[2].reg);
                }
                else
                {
                    addUseDef(info, ops[0].reg);
                    addUse(info, ops[1].reg);
                    addUse(info, ops[2].reg);
                }
                break;
            }

            default:
                SWC_ASSERT(false);
                break;
        }

        return info;
    }

    void collectRegOperands(const MicroInstr& inst, Store& store, SmallVector<RegOperandRef, 8>& out)
    {
        auto* ops = inst.ops(store);
        switch (inst.op)
        {
            case MicroInstrOpcode::End:
            case MicroInstrOpcode::Enter:
            case MicroInstrOpcode::Leave:
            case MicroInstrOpcode::Ignore:
            case MicroInstrOpcode::Label:
            case MicroInstrOpcode::Debug:
            case MicroInstrOpcode::LoadCallParam:
            case MicroInstrOpcode::LoadCallAddrParam:
            case MicroInstrOpcode::LoadCallZeroExtParam:
            case MicroInstrOpcode::StoreCallParam:
            case MicroInstrOpcode::Nop:
            case MicroInstrOpcode::Ret:
                break;

            case MicroInstrOpcode::SymbolRelocAddr:
            case MicroInstrOpcode::SymbolRelocValue:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::SetCondReg:
            case MicroInstrOpcode::ClearReg:
                addOperand(out, &ops[0].reg, false, true);
                break;

            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::CmpRegImm:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::Pop:
                addOperand(out, &ops[0].reg, false, true);
                break;

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                break;

            case MicroInstrOpcode::CallIndirect:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::JumpTable:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            case MicroInstrOpcode::PatchJump:
                break;

            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadCondRegReg:
                addOperand(out, &ops[0].reg, false, true);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                addOperand(out, &ops[0].reg, false, true);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                addOperand(out, &ops[0].reg, false, true);
                addOperand(out, &ops[1].reg, true, false);
                addOperand(out, &ops[2].reg, true, false);
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                addOperand(out, &ops[2].reg, true, false);
                break;

            case MicroInstrOpcode::LoadAmcMemImm:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::LoadMemReg:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::LoadMemImm:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::CmpRegReg:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::CmpMemReg:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::CmpMemImm:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::OpUnaryMem:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::OpUnaryReg:
                addOperand(out, &ops[0].reg, true, true);
                break;

            case MicroInstrOpcode::OpBinaryRegReg:
            {
                const auto op = ops[3].microOp;
                if (op == MicroOp::Exchange)
                {
                    addOperand(out, &ops[0].reg, true, true);
                    addOperand(out, &ops[1].reg, true, true);
                }
                else
                {
                    addOperand(out, &ops[0].reg, true, true);
                    addOperand(out, &ops[1].reg, true, false);
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryRegImm:
                addOperand(out, &ops[0].reg, true, true);
                break;

            case MicroInstrOpcode::OpBinaryRegMem:
                addOperand(out, &ops[0].reg, true, true);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::OpBinaryMemReg:
            {
                const auto op = ops[3].microOp;
                addOperand(out, &ops[0].reg, true, false);
                if (op == MicroOp::Exchange)
                    addOperand(out, &ops[1].reg, true, true);
                else
                    addOperand(out, &ops[1].reg, true, false);
                break;
            }
            case MicroInstrOpcode::OpBinaryMemImm:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::OpTernaryRegRegReg:
            {
                const auto op = ops[4].microOp;
                if (op == MicroOp::CompareExchange)
                {
                    addOperand(out, &ops[0].reg, true, true);
                    addOperand(out, &ops[1].reg, true, true);
                    addOperand(out, &ops[2].reg, true, false);
                }
                else
                {
                    addOperand(out, &ops[0].reg, true, true);
                    addOperand(out, &ops[1].reg, true, false);
                    addOperand(out, &ops[2].reg, true, false);
                }
                break;
            }

            default:
                SWC_ASSERT(false);
                break;
        }
    }
}

void MicroRegAllocPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    const auto& funcConv = CallConv::get(context.callConvKind);
    const auto& store    = context.operands->store();

    const uint32_t instructionCount = context.instructions->count();
    if (instructionCount == 0)
        return;

    std::unordered_map<uint32_t, uint32_t> regCallMask;
    std::vector<std::vector<uint32_t>>     liveOut(instructionCount);
    std::unordered_set<uint32_t>           live;

    uint32_t idx = instructionCount;
    for (auto& inst : context.instructions->viewMutReverse())
    {
        --idx;
        liveOut[idx].assign(live.begin(), live.end());

        const auto info = collectRegUseDef(inst, store);
        if (info.isCall)
        {
            const uint32_t bit = 1u << static_cast<uint32_t>(info.callConv);
            for (auto regKey : live)
                regCallMask[regKey] |= bit;
        }

        for (const auto& reg : info.defs)
        {
            if (reg.isVirtual())
                live.erase(reg.packed);
        }
        for (const auto& reg : info.uses)
        {
            if (reg.isVirtual())
                live.insert(reg.packed);
        }
    }

    std::unordered_set<uint32_t> intPersistentSet;
    std::unordered_set<uint32_t> floatPersistentSet;
    for (const auto& reg : funcConv.intPersistentRegs)
        intPersistentSet.insert(reg.packed);
    for (const auto& reg : funcConv.floatPersistentRegs)
        floatPersistentSet.insert(reg.packed);

    SmallVector<MicroReg, 16> freeIntTransient;
    SmallVector<MicroReg, 16> freeIntPersistent;
    SmallVector<MicroReg, 8>  freeFloatTransient;
    SmallVector<MicroReg, 8>  freeFloatPersistent;

    for (const auto& reg : funcConv.intRegs)
    {
        if (intPersistentSet.contains(reg.packed))
            freeIntPersistent.push_back(reg);
        else
            freeIntTransient.push_back(reg);
    }

    for (const auto& reg : funcConv.floatRegs)
    {
        if (floatPersistentSet.contains(reg.packed))
            freeFloatPersistent.push_back(reg);
        else
            freeFloatTransient.push_back(reg);
    }

    auto freePhysical = [&](MicroReg reg) {
        if (reg.isInt())
        {
            if (intPersistentSet.contains(reg.packed))
                freeIntPersistent.push_back(reg);
            else
                freeIntTransient.push_back(reg);
        }
        else if (reg.isFloat())
        {
            if (floatPersistentSet.contains(reg.packed))
                freeFloatPersistent.push_back(reg);
            else
                freeFloatTransient.push_back(reg);
        }
    };

    auto allocatePhysical = [&](MicroReg virtReg, uint32_t virtKey) -> MicroReg {
        const bool needsPersistent = regCallMask.contains(virtKey);
        if (virtReg.isVirtualInt())
        {
            SmallVector<MicroReg, 16>* pool = nullptr;
            if (needsPersistent)
                pool = &freeIntPersistent;
            else if (!freeIntTransient.empty())
                pool = &freeIntTransient;
            else
                pool = &freeIntPersistent;

            SWC_ASSERT(pool && !pool->empty());
            const auto reg = pool->back();
            pool->pop_back();
            return reg;
        }

        SWC_ASSERT(virtReg.isVirtualFloat());
        SmallVector<MicroReg, 8>* pool = nullptr;
        if (needsPersistent)
            pool = &freeFloatPersistent;
        else if (!freeFloatTransient.empty())
            pool = &freeFloatTransient;
        else
            pool = &freeFloatPersistent;

        SWC_ASSERT(pool && !pool->empty());
        const auto reg = pool->back();
        pool->pop_back();
        return reg;
    };

    std::unordered_map<uint32_t, MicroReg> mapping;
    std::unordered_map<uint32_t, uint32_t> liveStamp;
    uint32_t                               stamp = 1;

    idx = 0;
    for (auto& inst : context.instructions->viewMut())
    {
        ++stamp;
        for (auto regKey : liveOut[idx])
            liveStamp[regKey] = stamp;

        SmallVector<RegOperandRef, 8> regs;
        collectRegOperands(inst, context.operands->store(), regs);

        for (auto& regRef : regs)
        {
            const auto reg = *regRef.reg;
            if (!reg.isVirtual())
                continue;

            const uint32_t key = reg.packed;
            auto           it  = mapping.find(key);
            if (it == mapping.end())
            {
                const auto physReg = allocatePhysical(reg, key);
                it                 = mapping.emplace(key, physReg).first;
            }
            *regRef.reg = it->second;
        }

        for (auto it = mapping.begin(); it != mapping.end();)
        {
            auto liveIt = liveStamp.find(it->first);
            if (liveIt == liveStamp.end() || liveIt->second != stamp)
            {
                freePhysical(it->second);
                it = mapping.erase(it);
            }
            else
            {
                ++it;
            }
        }
        ++idx;
    }
}

SWC_END_NAMESPACE();
