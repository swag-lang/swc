#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroLabelHelpers.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/TaskContext.h"

// A runtime guard asked a second time.
//
//     cmp  i, 16                      cmp  i, 16
//     jb   A                          jb   A
//     ...report...                    ...report...
//   A:                              A:
//     ...                     ->      ...
//     cmp  i, 16                      cmp  i, 16
//     jb   B                          jmp  B
//     ...report...                    ...report...
//   B:                              B:
//
// `state[a] = f(state[a], state[b])` indexes the same array with the same
// index three times, and lowering guards each access on its own. The later
// guards test a value the first one already tested, with nothing in between
// but other guards, so they can only fail where the first one did - and that
// fault is already reported. The second jump becomes unconditional; its
// report is then unreachable, and its compare dead.
//
// Both jumps have to be guards. A program's own test of the same condition
// keeps its branch: after a report a hook chose to return from, the program
// still takes the arm the value selects.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        using MicroLabelHelpers::tryGetJumpTargetLabelId;

        // How far back an earlier guard is looked for.
        constexpr uint32_t K_MAX_SCAN = 96;

        struct GuardTest
        {
            MicroInstrOpcode op        = MicroInstrOpcode::Nop;
            MicroOpBits      bits      = MicroOpBits::Zero;
            MicroCond        cond      = MicroCond::Unconditional;
            uint32_t         leftId    = 0;
            uint32_t         rightId   = 0;
            uint64_t         immediate = 0;

            bool operator==(const GuardTest&) const = default;
        };

        bool readGuardTest(GuardTest& out, const Context& ctx, const MicroInstrRef cmpRef, const MicroCond cond)
        {
            const MicroInstr* cmp = ctx.instruction(cmpRef);
            if (!cmp || (cmp->op != MicroInstrOpcode::CmpRegImm && cmp->op != MicroInstrOpcode::CmpRegReg))
                return false;
            const MicroInstrOperand* ops = cmp->ops(*ctx.operands);
            if (!ops || !ops[0].reg.isVirtualInt())
                return false;

            const uint32_t left = ctx.ssa->reachingValueId(ops[0].reg, cmpRef);
            if (left == MicroSsaState::K_INVALID_VALUE)
                return false;

            out.op     = cmp->op;
            out.cond   = cond;
            out.leftId = left;
            if (cmp->op == MicroInstrOpcode::CmpRegImm)
            {
                if (ops[2].hasWideImmediateValue())
                    return false;
                out.bits      = ops[1].opBits;
                out.immediate = ops[2].valueU64;
                return true;
            }

            if (!ops[1].reg.isVirtualInt())
                return false;
            const uint32_t right = ctx.ssa->reachingValueId(ops[1].reg, cmpRef);
            if (right == MicroSsaState::K_INVALID_VALUE)
                return false;
            out.bits    = ops[2].opBits;
            out.rightId = right;
            return true;
        }

        // Whether `jumpRef` skips a straight-line report that ends at the label `joinRef`.
        bool skipsReport(Context& ctx, const MicroInstrRef jumpRef, const MicroInstrRef joinRef)
        {
            bool hasReport = false;
            auto walker    = MicroStorage::Iterator{ctx.storage, jumpRef};
            ++walker;
            for (; walker.current != joinRef; ++walker)
            {
                const MicroInstrRef ref  = walker.current;
                const MicroInstr*   inst = ref.isValid() ? &*walker : nullptr;
                if (!inst || inst->op == MicroInstrOpcode::Label || MicroInstrInfo::isTerminatorInstruction(*inst))
                    return false;
                hasReport = hasReport || ctx.isReportCall(ref);
            }
            return hasReport;
        }
    }

    bool tryDropRepeatedGuard(Context& ctx, MicroInstrRef cmpRef, const MicroInstr&)
    {
        if (!ctx.ssa || !ctx.builder)
            return false;

        const MicroInstrRef jumpRef = ctx.nextRef(cmpRef);
        const MicroInstr*   jump    = jumpRef.isValid() ? ctx.instruction(jumpRef) : nullptr;
        if (!jump || ctx.isClaimed(jumpRef))
            return false;
        const MicroInstrOperand* jumpOps  = jump->ops(*ctx.operands);
        uint32_t                 targetId = 0;
        if (!tryGetJumpTargetLabelId(targetId, *jump, jumpOps) || jumpOps[0].cpuCond == MicroCond::Unconditional)
            return false;

        GuardTest test;
        if (!readGuardTest(test, ctx, cmpRef, jumpOps[0].cpuCond))
            return false;

        // Back over straight-line code and over whole guards, to one that made the same
        // test. Every label crossed is the join of a guard and of nothing else, so the
        // guard found is the only way down to this one.
        const MicroControlFlowGraph& cfg      = ctx.builder->controlFlowGraph();
        bool                         repeated = false;
        uint32_t                     steps    = 0;
        auto                         walker   = MicroStorage::Iterator{ctx.storage, cmpRef};
        --walker;
        for (; walker.current.isValid() && !repeated && steps < K_MAX_SCAN; ++steps)
        {
            const MicroInstrRef ref  = walker.current;
            const MicroInstr*   inst = &*walker;
            if (inst->op != MicroInstrOpcode::Label)
            {
                if (MicroInstrInfo::isTerminatorInstruction(*inst))
                    return false;
                --walker;
                continue;
            }

            const uint32_t joinIndex = cfg.indexOf(ref);
            if (joinIndex == MicroControlFlowGraph::K_NO_INDEX || joinIndex == 0)
                return false;
            const auto  addressTaken = cfg.addressTakenLabelIndices();
            const auto& incoming     = cfg.predecessors(joinIndex);
            if (incoming.size() != 2 || std::ranges::find(addressTaken, joinIndex) != addressTaken.end())
                return false;
            const uint32_t jumpIndex = incoming[0] == joinIndex - 1 ? incoming[1] : incoming[0];
            if (jumpIndex >= joinIndex - 1 || (incoming[0] != joinIndex - 1 && incoming[1] != joinIndex - 1))
                return false;

            const MicroInstrRef      earlierJumpRef = cfg.instructionRefs()[jumpIndex];
            const MicroInstr*        earlierJump    = ctx.instruction(earlierJumpRef);
            const MicroInstrOperand* earlierOps     = earlierJump ? earlierJump->ops(*ctx.operands) : nullptr;
            uint32_t                 earlierTarget  = 0;
            if (!earlierJump || !tryGetJumpTargetLabelId(earlierTarget, *earlierJump, earlierOps) ||
                earlierOps[0].cpuCond == MicroCond::Unconditional || !skipsReport(ctx, earlierJumpRef, ref))
                return false;

            const MicroInstrRef earlierCmpRef = ctx.previousRef(earlierJumpRef);
            GuardTest           earlier;
            repeated = earlierCmpRef.isValid() && readGuardTest(earlier, ctx, earlierCmpRef, earlierOps[0].cpuCond) && earlier == test;
            walker   = MicroStorage::Iterator{ctx.storage, earlierJumpRef};
            --walker;
        }

        if (!repeated)
            return false;

        // The jump being resolved must be a guard as well: see the note above.
        const uint32_t joinIndex = cfg.indexOfLabel(targetId);
        if (joinIndex == MicroControlFlowGraph::K_NO_INDEX || !skipsReport(ctx, jumpRef, cfg.instructionRefs()[joinIndex]))
            return false;

        if (!ctx.claimAll({jumpRef}))
            return false;

        MicroInstrOperand newOps[3] = {jumpOps[0], jumpOps[1], jumpOps[2]};
        newOps[0].cpuCond           = MicroCond::Unconditional;
        ctx.emitRewrite(jumpRef, MicroInstrOpcode::JumpCond, newOps);
        return true;
    }

    namespace
    {
        // A value-borrow runtime call as code generation lays it out: its arguments copied into the
        // convention's first registers just before it, and the whole wrapped in an adjustment of the
        // stack pointer when the call is made at an unaligned depth.
        struct RuntimeCallShape
        {
            static constexpr uint32_t K_MAX_ARGS = 4;

            MicroInstrRef argRefs[K_MAX_ARGS] = {};
            uint32_t      argCount            = 0;
            MicroInstrRef subRef              = MicroInstrRef::invalid();
            MicroInstrRef addRef              = MicroInstrRef::invalid();
        };

        bool readStackAdjust(const Context& ctx, const MicroInstrRef adjustRef, const MicroOp op, uint64_t& outAmount)
        {
            const MicroInstr*        adjust = adjustRef.isValid() ? ctx.instruction(adjustRef) : nullptr;
            const MicroInstrOperand* ops    = adjust ? adjust->ops(*ctx.operands) : nullptr;
            if (!ops || adjust->op != MicroInstrOpcode::OpBinaryRegImm || ops[0].reg != ctx.stackPointer || ops[2].microOp != op || ops[3].hasWideImmediateValue())
                return false;
            outAmount = ops[3].valueU64;
            return true;
        }

        bool readRuntimeCallShape(RuntimeCallShape& out, const Context& ctx, MicroInstrRef callRef, const MicroInstr& callInst, uint32_t argCount)
        {
            SWC_ASSERT(argCount <= RuntimeCallShape::K_MAX_ARGS);
            const MicroInstrOperand* callOps = callInst.ops(*ctx.operands);
            if (!callOps || callInst.op != MicroInstrOpcode::CallLocal || !callInst.compilerSafetyCall)
                return false;
            const CallConv& conv = CallConv::get(callOps[0].callConv);
            if (conv.intArgRegs.size() < argCount)
                return false;

            out                     = {};
            out.argCount            = argCount;
            MicroInstrRef ref       = callRef;
            uint64_t      subAmount = 0;
            uint64_t      addAmount = 0;
            if (readStackAdjust(ctx, ctx.previousRef(callRef), MicroOp::Subtract, subAmount))
            {
                out.subRef = ctx.previousRef(callRef);
                out.addRef = ctx.nextRef(callRef);
                if (!readStackAdjust(ctx, out.addRef, MicroOp::Add, addAmount) || addAmount != subAmount)
                    return false;
                ref = out.subRef;
            }

            for (uint32_t step = 0; step < argCount; ++step)
            {
                ref                          = ctx.previousRef(ref);
                const MicroInstr*        def = ref.isValid() ? ctx.instruction(ref) : nullptr;
                const MicroInstrOperand* ops = def ? def->ops(*ctx.operands) : nullptr;
                if (!ops || def->numOperands == 0)
                    return false;
                if (def->op != MicroInstrOpcode::LoadRegReg && def->op != MicroInstrOpcode::LoadRegImm && def->op != MicroInstrOpcode::LoadRegPtrReloc &&
                    def->op != MicroInstrOpcode::LoadAddrRegMem && def->op != MicroInstrOpcode::LoadAddrAmcRegMem)
                    return false;
                const auto slot = std::ranges::find(conv.intArgRegs.begin(), conv.intArgRegs.begin() + argCount, ops[0].reg);
                if (slot == conv.intArgRegs.begin() + argCount)
                    return false;
                const size_t index = static_cast<size_t>(slot - conv.intArgRegs.begin());
                if (out.argRefs[index].isValid())
                    return false;
                out.argRefs[index] = ref;
            }

            return true;
        }

        void appendRuntimeCall(SmallVector<MicroInstrRef, 8>& refs, MicroInstrRef callRef, const RuntimeCallShape& shape)
        {
            for (uint32_t index = 0; index < shape.argCount; ++index)
                refs.push_back(shape.argRefs[index]);
            refs.push_back(callRef);
            if (shape.subRef.isValid())
            {
                refs.push_back(shape.subRef);
                refs.push_back(shape.addRef);
            }
        }

        // Erases calls with their argument copies, all of them or none; the values the copies
        // took die with them.
        bool eraseAll(Context& ctx, std::span<const MicroInstrRef> refs)
        {
            for (const MicroInstrRef ref : refs)
            {
                if (ctx.isClaimed(ref))
                    return false;
            }
            for (const MicroInstrRef ref : refs)
            {
                ctx.claimed.insert(ref.get());
                ctx.emitErase(ref);
            }
            return true;
        }
    }

    // A value-borrow check of a write into the function's own frame.
    //
    //     rcx = %address          (erased)
    //     rdx = %size             (erased)
    //     r8  = %location         (erased)
    //     r9  = %extentCache      (erased)
    //     call __valueBorrowWrite (erased)
    //
    // Code generation marks a write guard emitted while the function had no borrow of its own
    // open. Only such a borrow could cover this frame, so a fixed-size write whose address is
    // proved to lie in the frame cannot meet one. A write of a computed size keeps its check:
    // nothing bounds it to the frame. The extent test in front of the calls that stay is added
    // later, so nothing of it is left behind.
    bool tryDropFrameWriteGuard(Context& ctx, MicroInstrRef callRef, const MicroInstr& callInst)
    {
        if (!callInst.frameWriteGuard || !ctx.ssa)
            return false;

        // Address, size, source location and the module's extent cache.
        RuntimeCallShape shape;
        if (!readRuntimeCallShape(shape, ctx, callRef, callInst, 4))
            return false;

        const MicroInstr*        addressDef = ctx.instruction(shape.argRefs[0]);
        const MicroInstrOperand* addressOps = addressDef->ops(*ctx.operands);
        if (addressDef->op == MicroInstrOpcode::LoadRegImm || addressDef->op == MicroInstrOpcode::LoadRegPtrReloc ||
            !isFrameDerivedAddress(ctx, addressOps[1].reg, shape.argRefs[0]))
            return false;

        const MicroInstr*        sizeDef = ctx.instruction(shape.argRefs[1]);
        const MicroInstrOperand* sizeOps = sizeDef->ops(*ctx.operands);
        uint64_t                 size    = 0;
        if (sizeDef->op == MicroInstrOpcode::LoadRegReg)
        {
            if (!resolveIntConstant(size, ctx, sizeOps[1].reg, shape.argRefs[1], MicroOpBits::B64))
                return false;
        }
        else if (sizeDef->op != MicroInstrOpcode::LoadRegImm)
            return false;

        SmallVector<MicroInstrRef, 8> refs;
        appendRuntimeCall(refs, callRef, shape);
        return eraseAll(ctx, refs.span());
    }

    // Value borrows nothing can observe.
    //
    // A borrow is only ever judged by a write check, by the runtime's own checks of an allocator
    // release, or by code the borrowing function calls. A function that calls nothing but the
    // borrow registration itself and the panic reports, and keeps no write check, cannot reach any
    // of them while its borrows are open, so it registers none: a function reading the string or
    // the struct it received by value no longer pays for the registry on every call. Writes from
    // other threads are not the guard's to detect.
    void runDropUnobservedBorrows(Context& ctx)
    {
        if (!ctx.builder || !ctx.passContext || !ctx.passContext->taskContext || !ctx.passContext->taskContext->hasCompiler())
            return;

        const IdentifierManager& idMgr   = ctx.passContext->taskContext->idMgr();
        const IdentifierRef      enterId = idMgr.runtimeFunction(IdentifierManager::RuntimeFunctionKind::ValueBorrowEnter);
        const IdentifierRef      leaveId = idMgr.runtimeFunction(IdentifierManager::RuntimeFunctionKind::ValueBorrowLeave);

        struct BorrowCall
        {
            MicroInstrRef ref;
            uint32_t      argCount;
        };
        SmallVector<BorrowCall, 8> borrowCalls;
        FlatKeyMap<uint32_t>       borrowArgs;
        for (const MicroRelocation& relocation : ctx.builder->codeRelocations())
        {
            if (relocation.instructionRef.isInvalid() || !relocation.targetSymbol)
                continue;
            const IdentifierRef idRef = relocation.targetSymbol->idRef();
            // Record, address, size and source location; the release takes the record alone.
            if (idRef == enterId)
                borrowArgs.getOrInsert(relocation.instructionRef.get()) = 4;
            else if (idRef == leaveId)
                borrowArgs.getOrInsert(relocation.instructionRef.get()) = 1;
        }
        if (borrowArgs.empty())
            return;

        for (auto it = ctx.storage->view().begin(), endIt = ctx.storage->view().end(); it != endIt; ++it)
        {
            if (!MicroInstr::info(it->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                continue;
            if (const uint32_t* argCount = borrowArgs.find(it.current.get()); argCount && it->compilerSafetyCall)
                borrowCalls.push_back({it.current, *argCount});
            else if (!ctx.isReportCall(it.current))
                return;
        }

        // A registration left without its release would outlive the frame.
        SmallVector<MicroInstrRef, 8> refs;
        for (const BorrowCall& call : borrowCalls)
        {
            RuntimeCallShape shape;
            if (!readRuntimeCallShape(shape, ctx, call.ref, *ctx.instruction(call.ref), call.argCount))
                return;
            appendRuntimeCall(refs, call.ref, shape);
        }

        eraseAll(ctx, refs.span());
    }
}

SWC_END_NAMESPACE();
