#include "pch.h"
#include "Backend/Micro/Passes/Pass.ValueBorrowFastPath.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/RuntimeContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Address, size, source location and the module's extent cache.
    constexpr uint32_t K_GUARD_ARGS = 4;

    struct GuardCall
    {
        MicroInstrRef firstRef = MicroInstrRef::invalid(); // The test goes in front of it.
        MicroInstrRef lastRef  = MicroInstrRef::invalid(); // The skipped run ends with it.
        CallConvKind  callConv = CallConvKind::Swag;
    };

    bool isStackAdjust(const MicroInstr* inst, const MicroOperandStorage& operands, MicroReg stackPointer, MicroOp op)
    {
        const MicroInstrOperand* ops = inst ? inst->ops(operands) : nullptr;
        return ops && inst->op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg == stackPointer && ops[2].microOp == op;
    }

    // The arguments are copied into the convention's registers just before the call, which a call
    // made at an unaligned stack depth wraps in an adjustment of the stack pointer.
    bool readGuardCall(GuardCall& out, const MicroStorage& storage, const MicroOperandStorage& operands, MicroInstrRef callRef)
    {
        // A call the runtime source makes itself passes no extent cache.
        const MicroInstr*        call    = storage.ptr(callRef);
        const MicroInstrOperand* callOps = call ? call->ops(operands) : nullptr;
        if (!callOps || call->op != MicroInstrOpcode::CallLocal || !call->compilerSafetyCall)
            return false;
        const CallConv& conv = CallConv::get(callOps[0].callConv);
        if (conv.intArgRegs.size() < K_GUARD_ARGS)
            return false;

        out.callConv               = callOps[0].callConv;
        out.firstRef               = callRef;
        out.lastRef                = callRef;
        const MicroInstrRef subRef = storage.findPreviousInstructionRef(callRef);
        if (isStackAdjust(storage.ptr(subRef), operands, conv.stackPointer, MicroOp::Subtract))
        {
            const MicroInstrRef addRef = storage.findNextInstructionRef(callRef);
            if (!isStackAdjust(storage.ptr(addRef), operands, conv.stackPointer, MicroOp::Add))
                return false;
            out.firstRef = subRef;
            out.lastRef  = addRef;
        }

        bool          seen[K_GUARD_ARGS] = {};
        MicroInstrRef ref                = out.firstRef;
        for (uint32_t step = 0; step < K_GUARD_ARGS; ++step)
        {
            ref                          = storage.findPreviousInstructionRef(ref);
            const MicroInstr*        def = storage.ptr(ref);
            const MicroInstrOperand* ops = def ? def->ops(operands) : nullptr;
            if (!ops || def->numOperands == 0 || MicroInstr::info(def->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;
            const auto slot = std::ranges::find(conv.intArgRegs.begin(), conv.intArgRegs.begin() + K_GUARD_ARGS, ops[0].reg);
            if (slot == conv.intArgRegs.begin() + K_GUARD_ARGS)
                return false;
            const size_t index = static_cast<size_t>(slot - conv.intArgRegs.begin());
            if (seen[index])
                return false;
            seen[index] = true;
        }

        return storage.findNextInstructionRef(out.lastRef).isValid();
    }

    void insertLabel(MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef beforeRef, uint64_t labelId)
    {
        MicroInstrOperand ops[1] = {};
        ops[0].valueU64          = labelId;
        storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::Label, ops);
    }

    void insertJump(MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef beforeRef, MicroCond cond, uint64_t labelId)
    {
        MicroInstrOperand ops[3] = {};
        ops[0].cpuCond           = cond;
        ops[1].opBits            = MicroOpBits::B32;
        ops[2].valueU64          = labelId;
        storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::JumpCond, ops);
    }

    void insertLoad(MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef beforeRef, MicroReg reg, MicroReg base, uint64_t offset)
    {
        MicroInstrOperand ops[4] = {};
        ops[0].reg               = reg;
        ops[1].reg               = base;
        ops[2].opBits            = MicroOpBits::B64;
        ops[3].valueU64          = offset;
        storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::LoadRegMem, ops);
    }

    void insertCompare(MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef beforeRef, MicroReg left, MicroReg right)
    {
        MicroInstrOperand ops[3] = {};
        ops[0].reg               = left;
        ops[1].reg               = right;
        ops[2].opBits            = MicroOpBits::B64;
        storage.insertDerivedBefore(operands, beforeRef, MicroInstrOpcode::CmpRegReg, ops);
    }

    void insertExtentTest(MicroPassContext& context, const GuardCall& guard, MicroReg extent, MicroReg gap)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;
        const CallConv&      conv     = CallConv::get(guard.callConv);
        const MicroReg       address  = conv.intArgRegs[0];
        const MicroReg       size     = conv.intArgRegs[1];
        const MicroReg       cache    = conv.intArgRegs[3];
        const uint64_t       checkId  = context.builder->createLabel().get();
        const uint64_t       doneId   = context.builder->createLabel().get();
        const MicroInstrRef  at       = guard.firstRef;

        insertLabel(storage, operands, storage.findNextInstructionRef(guard.lastRef), doneId);

        insertLoad(storage, operands, at, extent, cache, 0);
        MicroInstrOperand nullOps[3] = {};
        nullOps[0].reg               = extent;
        nullOps[1].opBits            = MicroOpBits::B64;
        nullOps[2].setImmediateValue(ApInt(0, 64));
        storage.insertDerivedBefore(operands, at, MicroInstrOpcode::CmpRegImm, nullOps);
        insertJump(storage, operands, at, MicroCond::Equal, checkId);

        MicroInstrOperand highOps[4] = {};
        highOps[0].reg               = extent;
        highOps[1].reg               = address;
        highOps[2].opBits            = MicroOpBits::B64;
        highOps[3].valueU64          = offsetof(Runtime::ValueBorrowExtent, high);
        storage.insertDerivedBefore(operands, at, MicroInstrOpcode::CmpMemReg, highOps);
        insertJump(storage, operands, at, MicroCond::BelowOrEqual, doneId);

        insertLoad(storage, operands, at, gap, extent, offsetof(Runtime::ValueBorrowExtent, low));
        insertCompare(storage, operands, at, gap, address);
        insertJump(storage, operands, at, MicroCond::BelowOrEqual, checkId);

        MicroInstrOperand subOps[4] = {};
        subOps[0].reg               = gap;
        subOps[1].reg               = address;
        subOps[2].opBits            = MicroOpBits::B64;
        subOps[3].microOp           = MicroOp::Subtract;
        storage.insertDerivedBefore(operands, at, MicroInstrOpcode::OpBinaryRegReg, subOps);
        insertCompare(storage, operands, at, size, gap);
        insertJump(storage, operands, at, MicroCond::BelowOrEqual, doneId);

        insertLabel(storage, operands, at, checkId);
    }
}

Result MicroValueBorrowFastPathPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    // Code built outside a compiler, such as a call thunk, carries no guard.
    if (!context.builder || context.builder->codeRelocations().empty() || !context.taskContext || !context.taskContext->hasCompiler())
        return Result::Continue;

    const IdentifierRef        writeId = context.taskContext->idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::ValueBorrowWrite);
    SmallVector<MicroInstrRef> calls;
    for (const MicroRelocation& relocation : context.builder->codeRelocations())
    {
        if (relocation.instructionRef.isValid() && relocation.targetSymbol && relocation.targetSymbol->idRef() == writeId)
            calls.push_back(relocation.instructionRef);
    }
    if (calls.empty())
        return Result::Continue;

    uint32_t nextInt   = 0;
    uint32_t nextFloat = 0;
    MicroPassHelpers::computeNextVirtualRegIndices(context, nextInt, nextFloat);

    bool changed = false;
    for (const MicroInstrRef callRef : calls)
    {
        GuardCall guard;
        if (!readGuardCall(guard, *context.instructions, *context.operands, callRef))
            continue;
        if (nextInt > MicroReg::K_MAX_INDEX - 2)
            break;
        const MicroReg extent = MicroReg::virtualIntReg(nextInt++);
        const MicroReg gap    = MicroReg::virtualIntReg(nextInt++);
        insertExtentTest(context, guard, extent, gap);
        changed = true;
    }

    if (changed)
    {
        context.builder->invalidateControlFlowGraph();
        context.passChanged = true;
    }
    return Result::Continue;
}

SWC_END_NAMESPACE();
