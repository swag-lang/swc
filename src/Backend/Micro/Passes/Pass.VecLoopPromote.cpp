#include "pch.h"
#include "Backend/Micro/Passes/Pass.VecLoopPromote.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Runtime.h"
#include "Support/Core/SmallVector.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Assert.h"

// Loop-region promotion of 128-bit stack chunks. See the header for the
// contract.
//
// The pass mirrors LICM's loop discovery (per-instruction CFG, dominator
// tree, natural loops from back-edges) and the SLP vectorizer's memory model
// (addresses resolved through single-definition lea/copy chains down to a
// root register; the stack pointer and one incoming parameter are the only
// root pair ever assumed disjoint). The transformation itself never moves a
// computation: body accesses become register copies in place, and the only
// inserted instructions are one packed load before the loop header and one
// packed store on the loop's unique fall-through exit edge - both addressed
// directly off the stack pointer, whose value cannot change across a body
// that contains neither call nor push.

SWC_BEGIN_NAMESPACE();

namespace
{
    using NaturalLoop = MicroPassHelpers::NaturalLoop;

    constexpr uint32_t K_INVALID                = std::numeric_limits<uint32_t>::max();
    constexpr uint32_t K_CHUNK_BYTES            = 16;
    constexpr uint32_t K_MAX_ROOT_CHAIN         = 32;
    constexpr uint32_t K_MAX_PROMOTED_PER_LOOP  = 6;

    // How much is known about where a root register points; only the stack
    // pointer paired with one incoming parameter is ever assumed disjoint.
    enum class RootKind : uint8_t
    {
        StackPointer,
        Parameter,
        Unknown,
    };

    struct RegDefInfo
    {
        MicroInstrRef defRef   = MicroInstrRef::invalid();
        uint32_t      defIndex = 0;
        uint32_t      defCount = 0;
    };

    struct MemAccess
    {
        uint32_t instIndex  = K_INVALID;
        MicroReg rootReg    = MicroReg::invalid();
        uint64_t offset     = 0;
        uint32_t size       = 0;
        bool     isWrite    = false;
        bool     isVecLoad  = false;
        bool     isVecStore = false;
    };

    struct FunctionModel
    {
        MicroStorage*        storage  = nullptr;
        MicroOperandStorage* operands = nullptr;
        MicroReg             stackPointer;

        std::unordered_map<uint32_t, RegDefInfo> regDefs;
        uint32_t                                 firstCallIndex = K_INVALID;

        std::unordered_map<uint32_t, RootKind> rootKinds;

        RootKind classifyRoot(MicroReg reg, const RegDefInfo* def) const
        {
            if (reg == stackPointer)
                return RootKind::StackPointer;
            // A full-width copy out of a physical integer register before the
            // function's first call materializes an incoming ABI argument: the
            // caller formed that value before this frame existed, so it cannot
            // address the frame.
            if (def && def->defCount == 1 && def->defIndex < firstCallIndex)
            {
                const MicroInstr* defInst = storage->ptr(def->defRef);
                const MicroInstrOperand* defOps = defInst ? defInst->ops(*operands) : nullptr;
                if (defInst && defOps && defInst->op == MicroInstrOpcode::LoadRegReg &&
                    defOps[2].opBits == MicroOpBits::B64 && defOps[1].reg.isInt())
                {
                    return RootKind::Parameter;
                }
            }
            return RootKind::Unknown;
        }

        // Resolves a memory base register to (root register, accumulated
        // offset) through single-definition address chains, exactly like the
        // SLP vectorizer roots its accesses.
        bool resolveRoot(MicroReg baseReg, uint64_t& inOutOffset, MicroReg& outRoot, RootKind& outKind)
        {
            MicroReg reg = baseReg;
            for (uint32_t depth = 0; depth < K_MAX_ROOT_CHAIN; ++depth)
            {
                if (reg == stackPointer)
                {
                    outRoot = reg;
                    outKind = RootKind::StackPointer;
                    return true;
                }

                if (!reg.isVirtual())
                    return false;

                const auto defIt = regDefs.find(reg.packed);
                if (defIt == regDefs.end() || defIt->second.defCount != 1)
                    return false;

                const MicroInstr* defInst = storage->ptr(defIt->second.defRef);
                if (!defInst)
                    return false;

                const MicroInstrOperand* defOps = defInst->ops(*operands);
                if (defInst->op == MicroInstrOpcode::LoadAddrRegMem && defOps && !defOps[1].reg.isInstructionPointer())
                {
                    inOutOffset += defOps[3].valueU64;
                    reg = defOps[1].reg;
                    continue;
                }

                if (defInst->op == MicroInstrOpcode::LoadRegReg && defOps && defOps[2].opBits == MicroOpBits::B64 &&
                    (defOps[1].reg.isVirtual() || defOps[1].reg == stackPointer))
                {
                    reg = defOps[1].reg;
                    continue;
                }

                outRoot = reg;
                outKind = classifyRoot(reg, &defIt->second);
                return true;
            }

            return false;
        }
    };

    // Classifies one instruction's memory behavior. Returns false when the
    // instruction touches memory in a way the promotion cannot reason about.
    bool classifyMemAccess(FunctionModel& fn, const MicroInstr& inst, uint32_t instIndex, SmallVector<MemAccess>& outAccesses)
    {
        const MicroInstrOperand* ops = inst.ops(*fn.operands);
        if (!ops)
        {
            const MicroInstrFlags flags = MicroInstr::info(inst.op).flags;
            return !flags.has(MicroInstrFlagsE::WritesMemory) && !flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands);
        }

        MicroReg baseReg = MicroReg::invalid();
        uint64_t offset  = 0;
        uint32_t size    = 0;
        bool     isRead  = false;
        bool     isWrite = false;
        bool     vecLoad = false;
        bool     vecStore = false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
                baseReg = ops[1].reg;
                size    = getNumBytes(ops[2].opBits);
                offset  = ops[3].valueU64;
                isRead  = true;
                break;
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                baseReg = ops[1].reg;
                size    = getNumBytes(ops[3].opBits);
                offset  = ops[4].valueU64;
                isRead  = true;
                break;
            case MicroInstrOpcode::LoadVecRegMem:
                baseReg = ops[1].reg;
                size    = getNumBytes(ops[2].opBits);
                offset  = ops[3].valueU64;
                isRead  = true;
                vecLoad = ops[2].opBits == MicroOpBits::B128;
                break;
            case MicroInstrOpcode::LoadMemReg:
                baseReg = ops[0].reg;
                size    = getNumBytes(ops[2].opBits);
                offset  = ops[3].valueU64;
                isWrite = true;
                break;
            case MicroInstrOpcode::LoadMemImm:
                baseReg = ops[0].reg;
                size    = getNumBytes(ops[1].opBits);
                offset  = ops[2].valueU64;
                isWrite = true;
                break;
            case MicroInstrOpcode::StoreVecMemReg:
                baseReg  = ops[0].reg;
                size     = getNumBytes(ops[2].opBits);
                offset   = ops[3].valueU64;
                isWrite  = true;
                vecStore = ops[2].opBits == MicroOpBits::B128;
                break;
            case MicroInstrOpcode::CmpMemReg:
                baseReg = ops[0].reg;
                size    = getNumBytes(ops[2].opBits);
                offset  = ops[3].valueU64;
                isRead  = true;
                break;
            case MicroInstrOpcode::CmpMemImm:
                baseReg = ops[0].reg;
                size    = getNumBytes(ops[1].opBits);
                offset  = ops[2].valueU64;
                isRead  = true;
                break;
            case MicroInstrOpcode::OpBinaryRegMem:
                baseReg = ops[1].reg;
                size    = getNumBytes(ops[2].opBits);
                offset  = ops[4].valueU64;
                isRead  = true;
                break;
            case MicroInstrOpcode::OpBinaryMemReg:
                baseReg = ops[0].reg;
                size    = getNumBytes(ops[2].opBits);
                offset  = ops[4].valueU64;
                isRead  = true;
                isWrite = true;
                break;
            case MicroInstrOpcode::OpBinaryMemImm:
                baseReg = ops[0].reg;
                size    = getNumBytes(ops[1].opBits);
                offset  = ops[3].valueU64;
                isRead  = true;
                isWrite = true;
                break;
            case MicroInstrOpcode::OpUnaryMem:
                baseReg = ops[0].reg;
                size    = getNumBytes(ops[1].opBits);
                offset  = ops[3].valueU64;
                isRead  = true;
                isWrite = true;
                break;

            default:
            {
                // Anything else touching memory - push/pop, the variable-index
                // Amc forms, unknown future opcodes - is beyond this model.
                const MicroInstrFlags flags = MicroInstr::info(inst.op).flags;
                if (flags.has(MicroInstrFlagsE::WritesMemory) || flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
                    return false;
                if (inst.op == MicroInstrOpcode::LoadAmcRegMem ||
                    inst.op == MicroInstrOpcode::LoadSignedExtAmcRegMem ||
                    inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem ||
                    inst.op == MicroInstrOpcode::CmpAmcImm)
                    return false;
                return true;
            }
        }

        if (baseReg.isInstructionPointer())
            return false;

        MicroReg rootReg;
        RootKind rootKind = RootKind::Unknown;
        if (!fn.resolveRoot(baseReg, offset, rootReg, rootKind))
            return false;
        if (rootKind == RootKind::Unknown)
            return false;

        MemAccess access;
        access.instIndex  = instIndex;
        access.rootReg    = rootReg;
        access.offset     = offset;
        access.size       = std::max<uint32_t>(size, 1);
        access.isWrite    = isWrite;
        access.isVecLoad  = isRead && vecLoad;
        access.isVecStore = isWrite && vecStore;
        outAccesses.push_back(access);
        return true;
    }

    // Attempts the promotion on one loop. Returns true when the IR changed.
    bool promoteLoop(MicroPassContext& context, FunctionModel& fn, const MicroControlFlowGraph& cfg, const NaturalLoop& loop, std::span<const MicroInstrRef> instrRefs)
    {
        MicroStorage&        storage  = *fn.storage;
        MicroOperandStorage& operands = *fn.operands;
        const uint32_t       n        = cfg.instructionCount();

        // ---- A clean preheader, exactly like LICM requires one: a single
        //      external predecessor that is the linear predecessor and falls
        //      through into the header. ----
        uint32_t externalPredCount = 0;
        for (const uint32_t p : cfg.predecessors(loop.header))
        {
            if (p < n && !loop.inBody[p])
                ++externalPredCount;
        }
        if (externalPredCount != 1)
            return false;

        const MicroInstrRef headerRef = instrRefs[loop.header];
        const MicroInstrRef prevRef   = storage.findPreviousInstructionRef(headerRef);
        if (!prevRef.isValid())
            return false;
        if (loop.header == 0 || instrRefs[loop.header - 1] != prevRef || loop.inBody[loop.header - 1])
            return false;
        const MicroInstr* prevInst = storage.ptr(prevRef);
        if (!prevInst)
            return false;
        const MicroInstrFlags prevFlags = MicroInstr::info(prevInst->op).flags;
        const bool            prevIsUncondJump =
            prevFlags.has(MicroInstrFlagsE::JumpInstruction) && !prevFlags.has(MicroInstrFlagsE::ConditionalJump);
        const bool prevIsUncondTerm =
            prevFlags.has(MicroInstrFlagsE::TerminatorInstruction) && !prevFlags.has(MicroInstrFlagsE::ConditionalJump);
        if (prevIsUncondJump || prevIsUncondTerm)
            return false;

        // ---- A unique fall-through exit edge: the sunk store lands between
        //      the exiting instruction and its linear successor, which only
        //      the fall-through path executes (a jump to a label after that
        //      point cannot land on it). ----
        uint32_t exitFrom = K_INVALID;
        uint32_t exitTo   = K_INVALID;
        for (uint32_t u = 0; u < n; ++u)
        {
            if (!loop.inBody[u])
                continue;
            for (const uint32_t v : cfg.successors(u))
            {
                if (v < n && !loop.inBody[v])
                {
                    if (exitFrom != K_INVALID)
                        return false;
                    exitFrom = u;
                    exitTo   = v;
                }
            }
        }
        if (exitFrom == K_INVALID || exitTo != exitFrom + 1)
            return false;
        if (storage.findNextInstructionRef(instrRefs[exitFrom]) != instrRefs[exitTo])
            return false;

        // ---- Scan every body instruction's memory behavior; a call, a
        //      stack-pointer adjustment, or an unexplainable access
        //      disqualifies the whole loop (the promoted load and store are
        //      re-addressed off the stack pointer, so its value must be the
        //      same at the preheader, inside the body, and at the exit). ----
        SmallVector<MemAccess> accesses;
        for (uint32_t i = 0; i < n; ++i)
        {
            if (!loop.inBody[i])
                continue;
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            if (!inst)
                return false;
            if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;
            const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
            for (const MicroReg def : useDef.defs)
            {
                if (def == fn.stackPointer)
                    return false;
            }
            if (!classifyMemAccess(fn, *inst, i, accesses))
                return false;
        }

        // ---- Aliasing policy, copied from the SLP vectorizer: the roots the
        //      body touches must be provably pairwise disjoint, which means
        //      one root, or the stack pointer plus one incoming parameter. ----
        SmallVector<MicroReg> roots;
        bool                  hasStackRoot = false;
        bool                  hasParamRoot = false;
        for (const MemAccess& access : accesses)
        {
            bool known = false;
            for (const MicroReg root : roots)
                known = known || root == access.rootReg;
            if (!known)
            {
                roots.push_back(access.rootReg);
                if (access.rootReg == fn.stackPointer)
                    hasStackRoot = true;
                else
                    hasParamRoot = true;
            }
        }
        if (roots.size() > 2)
            return false;
        if (roots.size() == 2 && (!hasStackRoot || !hasParamRoot))
            return false;

        // ---- Candidate chunks: 16-byte frame locations whose every
        //      overlapping body access is the full-width packed load or store
        //      of exactly that location. ----
        struct Chunk
        {
            uint64_t offset   = 0;
            bool     hasStore = false;
            bool     hasLoad  = false;
        };
        std::vector<Chunk> chunks;
        for (const MemAccess& access : accesses)
        {
            if (!access.isVecLoad && !access.isVecStore)
                continue;
            if (access.rootReg != fn.stackPointer)
                continue;
            bool found = false;
            for (Chunk& chunk : chunks)
            {
                if (chunk.offset == access.offset)
                {
                    chunk.hasStore = chunk.hasStore || access.isVecStore;
                    chunk.hasLoad  = chunk.hasLoad || access.isVecLoad;
                    found          = true;
                    break;
                }
            }
            if (!found)
                chunks.push_back(Chunk{.offset = access.offset, .hasStore = access.isVecStore, .hasLoad = access.isVecLoad});
        }
        if (chunks.empty())
            return false;

        std::ranges::sort(chunks, [](const Chunk& a, const Chunk& b) { return a.offset < b.offset; });

        SmallVector<Chunk> promoted;
        for (const Chunk& chunk : chunks)
        {
            if (promoted.size() >= K_MAX_PROMOTED_PER_LOOP)
                break;

            bool clean = true;
            for (const MemAccess& access : accesses)
            {
                if (access.rootReg != fn.stackPointer)
                    continue;
                const bool overlaps = access.offset < chunk.offset + K_CHUNK_BYTES &&
                                      chunk.offset < access.offset + access.size;
                if (!overlaps)
                    continue;
                const bool isChunkAccess = (access.isVecLoad || access.isVecStore) &&
                                           access.offset == chunk.offset && access.size == K_CHUNK_BYTES;
                if (!isChunkAccess)
                {
                    clean = false;
                    break;
                }
            }
            if (clean)
                promoted.push_back(chunk);
        }
        if (promoted.empty())
            return false;

        // ---- Transform. Body accesses become copies in place; the packed
        //      load and store are re-addressed directly off the stack pointer
        //      (the accumulated chain offset is stack-relative, and a body
        //      with neither call nor push cannot move the stack pointer). ----
        uint32_t nextVirtualFloatRegIndex = MicroPassHelpers::computeNextVirtualFloatRegIndex(context);

        for (const Chunk& chunk : promoted)
        {
            SWC_ASSERT(nextVirtualFloatRegIndex < MicroReg::K_MAX_INDEX);
            const MicroReg promotedReg = MicroReg::virtualFloatReg(nextVirtualFloatRegIndex++);

            for (const MemAccess& access : accesses)
            {
                if (access.rootReg != fn.stackPointer || access.offset != chunk.offset)
                    continue;
                if (!access.isVecLoad && !access.isVecStore)
                    continue;

                MicroInstr* inst = storage.ptr(instrRefs[access.instIndex]);
                if (!inst)
                    continue;
                MicroInstrOperand* ops = inst->ops(operands);
                if (!ops)
                    continue;

                if (inst->op == MicroInstrOpcode::LoadVecRegMem)
                {
                    // dst = load [chunk]  ->  dst = copy promotedReg
                    ops[1].reg        = promotedReg;
                    ops[2].opBits     = MicroOpBits::B128;
                    inst->op          = MicroInstrOpcode::LoadRegReg;
                    inst->numOperands = 3;
                }
                else if (inst->op == MicroInstrOpcode::StoreVecMemReg)
                {
                    // store [chunk], src  ->  promotedReg = copy src
                    const MicroReg src = ops[1].reg;
                    ops[0].reg         = promotedReg;
                    ops[1].reg         = src;
                    ops[2].opBits      = MicroOpBits::B128;
                    inst->op           = MicroInstrOpcode::LoadRegReg;
                    inst->numOperands  = 3;
                }
            }

            std::array<MicroInstrOperand, 4> loadOps;
            loadOps[0].reg      = promotedReg;
            loadOps[1].reg      = fn.stackPointer;
            loadOps[2].opBits   = MicroOpBits::B128;
            loadOps[3].valueU64 = chunk.offset;
            storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::LoadVecRegMem, loadOps);

            if (chunk.hasStore)
            {
                std::array<MicroInstrOperand, 4> storeOps;
                storeOps[0].reg      = fn.stackPointer;
                storeOps[1].reg      = promotedReg;
                storeOps[2].opBits   = MicroOpBits::B128;
                storeOps[3].valueU64 = chunk.offset;
                storage.insertDerivedBefore(operands, instrRefs[exitTo], MicroInstrOpcode::StoreVecMemReg, storeOps);
            }
        }

        return true;
    }
}

Result MicroVecLoopPromotePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/VecLoopPromote");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    if (!context.builder)
        return Result::Continue;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    // The shapes this pass rewrites only exist once the SLP vectorizer has
    // produced packed memory accesses: same build-configuration gate, then the
    // cached loop test, and only then a scan for packed accesses - so the
    // overwhelmingly common scalar or loop-free function pays one or two flag
    // reads per sweep.
    const Runtime::BuildCfgBackend& backendCfg = context.builder->backendBuildCfg();
    if (!backendCfg.optimize || backendCfg.cpuVectorize == Runtime::BuildCfgBackendCpuVectorize::None)
        return Result::Continue;

    if (!context.builder->controlFlowGraph().hasLoop())
        return Result::Continue;

    bool hasVecMem = false;
    for (const MicroInstr& inst : storage.view())
    {
        if (inst.op == MicroInstrOpcode::LoadVecRegMem || inst.op == MicroInstrOpcode::StoreVecMemReg)
        {
            hasVecMem = true;
            break;
        }
    }
    if (!hasVecMem)
        return Result::Continue;

    const MicroReg stackPointer = CallConv::get(context.callConvKind).stackPointer;
    if (!stackPointer.isValid())
        return Result::Continue;

    const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
    if (cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
        return Result::Continue;

    const uint32_t n = cfg.instructionCount();
    if (n == 0)
        return Result::Continue;

    const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
    if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
        return Result::Continue;

    const auto instrRefs = cfg.instructionRefs();

    FunctionModel fn;
    fn.storage      = &storage;
    fn.operands     = &operands;
    fn.stackPointer = stackPointer;

    for (uint32_t i = 0; i < n; ++i)
    {
        const MicroInstr* inst = storage.ptr(instrRefs[i]);
        if (!inst)
            return Result::Continue;

        if (fn.firstCallIndex == K_INVALID && MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
            fn.firstCallIndex = i;

        const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
        for (const MicroReg reg : useDef.defs)
        {
            if (!reg.isVirtual())
                continue;
            RegDefInfo& info = fn.regDefs[reg.packed];
            info.defCount++;
            info.defRef   = instrRefs[i];
            info.defIndex = i;
        }
    }

    const MicroPassHelpers::MicroDomTree dom = MicroPassHelpers::computeInstructionDominators(cfg, entry);

    std::unordered_map<uint32_t, NaturalLoop> loopsByHeader = MicroPassHelpers::findNaturalLoops(cfg, dom);
    if (loopsByHeader.empty())
        return Result::Continue;

    std::vector<NaturalLoop*> loops;
    loops.reserve(loopsByHeader.size());
    for (auto& loop : loopsByHeader | std::views::values)
        loops.push_back(&loop);
    std::ranges::sort(loops, [](const NaturalLoop* a, const NaturalLoop* b) {
        if (a->bodySize != b->bodySize)
            return a->bodySize < b->bodySize;
        return a->header < b->header;
    });

    // One loop per run, innermost first: the enclosing optimization loop
    // re-runs the pass on the fresh IR, which is how a chunk climbs out of a
    // loop nest one level per sweep, and how the analysis never reasons about
    // instructions this very run displaced.
    for (const NaturalLoop* loop : loops)
    {
        if (promoteLoop(context, fn, cfg, *loop, instrRefs))
        {
            context.passChanged = true;
            if (context.ssaState)
                context.ssaState->invalidate();
            context.builder->invalidateControlFlowGraph();
            return Result::Continue;
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
