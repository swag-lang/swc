#include "pch.h"
#include "Backend/Micro/Passes/Pass.SlpVectorize.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Runtime.h"
#include "Support/Report/Assert.h"

// Superword-level vectorization of straight-line blocks.
//
// The pass rebuilds each block's scalar dataflow as a value graph whose values
// carry 32-bit-lane semantics: register copies and 64<-32 zero-extensions are
// transparent, additions performed at 64 bits count as 32-bit lane additions
// (the low half of a wider add is the modular 32-bit sum), and in-block stores
// forward their value to later loads of the same location. Memory addresses
// are resolved through hoisted address chains down to a stable root register,
// so `%a = &[%root + 16]` followed by `[%a] = v` is understood as a store to
// (root, 16).
//
// Seeds are the block's final 32-bit stores: four of them covering one
// contiguous 16-byte chunk of a root become one candidate group. Each group
// grows a tree by walking the four lane values in lockstep - four isomorphic
// binary operations recurse into their operands, four adjacent loads of block
// -entry memory become one packed load, a lane permutation of an already
// -vectorized tuple becomes one shuffle, and equal shift or rotate immediates
// become packed shifts (a rotate expands to shift/shift/or). Shared subtrees
// are memoized on the ordered lane tuple, which is what turns the second half
// of a ChaCha20 double round into shuffles of the first half's vectors
// instead of a recomputation.
//
// The transformation only deletes stores: the packed computation is inserted
// at the position of the group's first store, and every scalar store to the
// vectorized locations is erased. The scalar chain that fed them is left in
// place - it has become dead code, and the cleanup sweep that follows the
// pass removes it. Deleting a store is only sound if nothing still reads the
// location afterwards, so any surviving load of a vectorized location that
// sits after the first deleted store must itself be provably dead once the
// stores are gone; that check walks the SSA use lists, refusing phis, side
// effects, and instructions whose CPU flags may be consumed.
//
// Aliasing: all memory operations of a block must resolve against at most two
// roots - the stack pointer and one other - before any group is attempted.
// The frame-privacy assumption (an incoming pointer cannot alias the
// function's own frame) is what allows the pair; two unknown non-frame roots
// are never assumed disjoint, and any unresolvable memory operation in the
// block disables it entirely.

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID_ID      = std::numeric_limits<uint32_t>::max();
    constexpr uint32_t K_LANE_COUNT      = 4;
    constexpr uint32_t K_LANE_BYTES      = 4;
    constexpr uint32_t K_CHUNK_BYTES     = 16;
    constexpr uint32_t K_MAX_PLAN_INSTRS = 4096;
    constexpr uint32_t K_MAX_TREE_DEPTH  = 512;
    constexpr uint32_t K_MAX_ROOT_CHAIN  = 32;

    // Lane operations the value graph models. Wider scalar forms map onto
    // these when their low 32 bits behave like the 32-bit operation.
    enum class LaneOp : uint8_t
    {
        Add,
        Sub,
        And,
        Or,
        Xor,
        ShiftLeft,
        ShiftRight,
        RotateLeft,
    };

    enum class SlpValueKind : uint8_t
    {
        Opaque,
        Const,
        Load,
        BinaryRegReg,
        BinaryRegImm,
    };

    struct SlpValue
    {
        SlpValueKind kind = SlpValueKind::Opaque;
        LaneOp       op   = LaneOp::Add;
        uint32_t     lhs  = K_INVALID_ID;
        uint32_t     rhs  = K_INVALID_ID;
        uint64_t     imm  = 0;

        uint32_t loadRootKey = K_INVALID_ID;
        uint64_t loadOffset  = 0;
        uint32_t loadEpoch   = 0;
    };

    struct SlpValueTable
    {
        std::vector<SlpValue>                               values;
        std::unordered_map<uint64_t, std::vector<uint32_t>> buckets;

        static uint64_t hashOf(const SlpValue& v)
        {
            uint64_t   h   = 1469598103934665603ull;
            const auto mix = [&h](uint64_t x) {
                h ^= x;
                h *= 1099511628211ull;
            };
            mix(static_cast<uint64_t>(v.kind));
            mix(static_cast<uint64_t>(v.op));
            mix(v.lhs);
            mix(v.rhs);
            mix(v.imm);
            mix(v.loadRootKey);
            mix(v.loadOffset);
            mix(v.loadEpoch);
            return h;
        }

        static bool equal(const SlpValue& a, const SlpValue& b)
        {
            if (a.kind != b.kind)
                return false;
            switch (a.kind)
            {
                case SlpValueKind::Const:
                    return a.imm == b.imm;
                case SlpValueKind::Load:
                    return a.loadRootKey == b.loadRootKey && a.loadOffset == b.loadOffset && a.loadEpoch == b.loadEpoch;
                case SlpValueKind::BinaryRegReg:
                    return a.op == b.op && a.lhs == b.lhs && a.rhs == b.rhs;
                case SlpValueKind::BinaryRegImm:
                    return a.op == b.op && a.lhs == b.lhs && a.imm == b.imm;
                case SlpValueKind::Opaque:
                    return false;
            }
            return false;
        }

        uint32_t makeOpaque()
        {
            values.push_back(SlpValue{});
            return static_cast<uint32_t>(values.size() - 1);
        }

        uint32_t intern(const SlpValue& v)
        {
            // No commutative canonicalization: tuples are matched lane by
            // lane, and swapping operands in one lane but not its siblings
            // would misalign the operand roles across the group. The scan
            // produces consistent shapes for isomorphic code as written.
            const uint64_t h      = hashOf(v);
            auto&          bucket = buckets[h];
            for (const uint32_t id : bucket)
            {
                if (equal(values[id], v))
                    return id;
            }

            values.push_back(v);
            const auto id = static_cast<uint32_t>(values.size() - 1);
            bucket.push_back(id);
            return id;
        }

        const SlpValue& get(uint32_t id) const { return values[id]; }
    };

    struct MemLocation
    {
        uint32_t      valueId          = K_INVALID_ID;
        uint32_t      epoch            = 0;
        bool          hasNonPlainStore = false;
        bool          lastIsPlain32    = false;
        MicroInstrRef lastStoreRef     = MicroInstrRef::invalid();
    };

    struct StoreRecord
    {
        MicroInstrRef instRef = MicroInstrRef::invalid();
        uint32_t      pos     = 0;
        uint32_t      rootKey = K_INVALID_ID;
        uint64_t      offset  = 0;
        uint32_t      size    = 0;
        bool          plain32 = false;
    };

    struct LoadRecord
    {
        MicroInstrRef instRef = MicroInstrRef::invalid();
        uint32_t      pos     = 0;
        uint32_t      rootKey = K_INVALID_ID;
        uint64_t      offset  = 0;
        uint32_t      size    = 0;
        MicroReg      dstReg  = MicroReg::invalid();
    };

    // How much is known about where a root register points, which is what
    // decides whether two roots may be assumed disjoint.
    enum class RootKind : uint8_t
    {
        // The stack pointer: everything it addresses is this frame.
        StackPointer,
        // A value the caller computed and passed in, so it was formed before
        // this frame existed and cannot point into it.
        Parameter,
        // Anything else. Never assumed disjoint from another root.
        Unknown,
    };

    struct RootInfo
    {
        MicroReg reg  = MicroReg::invalid();
        RootKind kind = RootKind::Unknown;
        // Global position of the root register's single definition, or
        // K_INVALID_ID when the root is the stack pointer (always available).
        uint32_t defPos = K_INVALID_ID;
    };

    struct PlanInstr
    {
        enum class Kind : uint8_t
        {
            LoadVec,
            StoreVec,
            Copy,
            BinaryRegReg,
            BinaryRegImm,
            // Non-destructive forms: the destination is a register of its own,
            // so the packed value feeding the operation is not overwritten and
            // needs no copy. Emitted instead of the Copy pairs above wherever
            // the encoder has the VEX encodings.
            BinaryRegRegReg,
            BinaryRegRegImm,
            Shuffle,
        };

        Kind     kind       = Kind::Copy;
        uint32_t dst        = 0;
        uint32_t src        = 0;
        uint32_t src2       = 0;
        MicroOp  op         = MicroOp::VecXor;
        uint64_t imm        = 0;
        uint32_t rootKey    = K_INVALID_ID;
        uint64_t baseOffset = 0;
    };

    struct RegDefInfo
    {
        MicroInstrRef defRef   = MicroInstrRef::invalid();
        uint32_t      defPos   = 0;
        uint32_t      defCount = 0;
    };

    // ------------------------------------------------------------------
    // Whole-function context

    struct SlpFunctionContext
    {
        MicroPassContext*    context  = nullptr;
        MicroStorage*        storage  = nullptr;
        MicroOperandStorage* operands = nullptr;
        const Encoder*       encoder  = nullptr;

        // Single-definition map over virtual registers, for address rooting.
        std::unordered_map<uint32_t, RegDefInfo> regDefs;

        // Root registry: register -> dense key.
        std::unordered_map<uint32_t, uint32_t> rootKeys;
        std::vector<RootInfo>                  roots;

        const MicroSsaState* ssa = nullptr;

        uint32_t nextVirtualFloatRegIndex = 0;
        // Position of the function's first call. A register copied out of a
        // physical register before it holds an incoming ABI argument; after
        // it, the same shape is a returned value of unknown provenance.
        uint32_t firstCallPos = K_INVALID_ID;

        uint32_t rootKeyFor(MicroReg reg, RootKind kind, uint32_t defPos)
        {
            const auto it = rootKeys.find(reg.packed);
            if (it != rootKeys.end())
                return it->second;
            const auto key = static_cast<uint32_t>(roots.size());
            rootKeys.emplace(reg.packed, key);
            roots.push_back(RootInfo{.reg = reg, .kind = kind, .defPos = defPos});
            return key;
        }
    };

    // ------------------------------------------------------------------
    // Per-block scan state

    struct BlockInstr
    {
        MicroInstrRef instRef = MicroInstrRef::invalid();
        MicroInstr*   inst    = nullptr;
        uint32_t      pos     = 0;
    };

    struct BlockScan
    {
        std::vector<BlockInstr> instrs;

        SlpValueTable values;
        // Current lane value per register (32-bit view of its low bits).
        std::unordered_map<uint32_t, uint32_t> regValues;
        // Stable value for registers live at block entry.
        std::unordered_map<uint32_t, uint32_t> entryValues;
        // Memory state per (rootKey, offset), 4-byte aligned slots.
        std::unordered_map<uint64_t, MemLocation> locations;

        std::vector<StoreRecord> stores;
        std::vector<LoadRecord>  loads;

        bool hasUnresolvedMemRead  = false;
        bool hasUnresolvedMemWrite = false;

        static uint64_t locationKey(uint32_t rootKey, uint64_t offset)
        {
            return (static_cast<uint64_t>(rootKey) << 40) ^ offset;
        }
    };

    // ------------------------------------------------------------------

    bool isStackPointer(const SlpFunctionContext& fn, MicroReg reg)
    {
        return fn.encoder && reg == fn.encoder->stackPointerReg();
    }

    // Resolves a memory operand's base register to (rootKey, extra offset) by
    // walking single-definition address chains: `lea` style address loads and
    // 64-bit register copies. Fails on multi-definition bases and on anything
    // it does not understand, which makes the caller treat the access as
    // unresolvable.
    bool resolveRoot(SlpFunctionContext& fn, MicroReg baseReg, uint64_t& inOutOffset, uint32_t& outRootKey)
    {
        MicroReg reg = baseReg;
        for (uint32_t depth = 0; depth < K_MAX_ROOT_CHAIN; ++depth)
        {
            if (isStackPointer(fn, reg))
            {
                outRootKey = fn.rootKeyFor(reg, RootKind::StackPointer, K_INVALID_ID);
                return true;
            }

            if (!reg.isVirtual())
                return false;

            const auto defIt = fn.regDefs.find(reg.packed);
            if (defIt == fn.regDefs.end() || defIt->second.defCount != 1)
                return false;

            const MicroInstr* defInst = fn.storage->ptr(defIt->second.defRef);
            if (!defInst)
                return false;

            const MicroInstrOperand* defOps = defInst->ops(*fn.operands);
            if (defInst->op == MicroInstrOpcode::LoadAddrRegMem && defOps && !defOps[1].reg.isInstructionPointer())
            {
                inOutOffset += defOps[3].valueU64;
                reg = defOps[1].reg;
                continue;
            }

            // Follow full-width pointer copies into registers the walk can
            // keep reasoning about.
            if (defInst->op == MicroInstrOpcode::LoadRegReg && defOps && defOps[2].opBits == MicroOpBits::B64 &&
                (defOps[1].reg.isVirtual() || isStackPointer(fn, defOps[1].reg)))
            {
                reg = defOps[1].reg;
                continue;
            }

            // The register itself is the root value. A copy out of a physical
            // register taken before the function's first call is an incoming
            // argument: the caller formed it before this frame existed, which
            // is what makes it provably disjoint from the frame.
            auto kind = RootKind::Unknown;
            if (defInst->op == MicroInstrOpcode::LoadRegReg && defOps && defOps[2].opBits == MicroOpBits::B64 &&
                defOps[1].reg.isInt() && defIt->second.defPos < fn.firstCallPos)
            {
                kind = RootKind::Parameter;
            }

            outRootKey = fn.rootKeyFor(reg, kind, defIt->second.defPos);
            return true;
        }

        return false;
    }

    uint32_t entryValueFor(BlockScan& scan, MicroReg reg)
    {
        const auto it = scan.entryValues.find(reg.packed);
        if (it != scan.entryValues.end())
            return it->second;
        const uint32_t id = scan.values.makeOpaque();
        scan.entryValues.emplace(reg.packed, id);
        return id;
    }

    uint32_t currentValue(BlockScan& scan, MicroReg reg)
    {
        const auto it = scan.regValues.find(reg.packed);
        if (it != scan.regValues.end())
            return it->second;
        return scan.regValues.emplace(reg.packed, entryValueFor(scan, reg)).first->second;
    }

    void setValue(BlockScan& scan, MicroReg reg, uint32_t valueId)
    {
        scan.regValues[reg.packed] = valueId;
    }

    void setOpaque(BlockScan& scan, MicroReg reg)
    {
        setValue(scan, reg, scan.values.makeOpaque());
    }

    // Every register the instruction defines becomes an opaque value.
    void setDefsOpaque(const SlpFunctionContext& fn, BlockScan& scan, const MicroInstr& inst)
    {
        const MicroInstrUseDef useDef = inst.collectUseDef(*fn.operands, fn.encoder);
        for (const MicroReg reg : useDef.defs)
            setOpaque(scan, reg);
    }

    void killLocationRange(BlockScan& scan, uint32_t rootKey, uint64_t offset, uint32_t size, MicroInstrRef storeRef)
    {
        const uint64_t first = offset & ~static_cast<uint64_t>(K_LANE_BYTES - 1);
        for (uint64_t o = first; o < offset + size; o += K_LANE_BYTES)
        {
            MemLocation& loc     = scan.locations[BlockScan::locationKey(rootKey, o)];
            loc.valueId          = K_INVALID_ID;
            loc.epoch            = loc.epoch + 1;
            loc.hasNonPlainStore = true;
            loc.lastIsPlain32    = false;
            loc.lastStoreRef     = storeRef;
        }
    }

    // ------------------------------------------------------------------
    // Scan helpers per instruction shape

    bool isLaneTransparentCopy(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (inst.op == MicroInstrOpcode::LoadRegReg)
            return (ops[2].opBits == MicroOpBits::B32 || ops[2].opBits == MicroOpBits::B64) && !ops[0].reg.isAnyFloat() && !ops[1].reg.isAnyFloat();
        if (inst.op == MicroInstrOpcode::LoadZeroExtRegReg)
            return ops[2].opBits == MicroOpBits::B64 && ops[3].opBits == MicroOpBits::B32;
        return false;
    }

    bool laneOpForBinaryRegReg(MicroOp op, MicroOpBits opBits, LaneOp& outOp)
    {
        if (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64)
            return false;

        switch (op)
        {
            case MicroOp::Add:
                outOp = LaneOp::Add;
                return true;
            case MicroOp::Subtract:
                outOp = LaneOp::Sub;
                return true;
            case MicroOp::And:
                outOp = LaneOp::And;
                return true;
            case MicroOp::Or:
                outOp = LaneOp::Or;
                return true;
            case MicroOp::Xor:
                outOp = LaneOp::Xor;
                return true;
            default:
                return false;
        }
    }

    bool laneOpForBinaryRegImm(MicroOp op, MicroOpBits opBits, uint64_t imm, LaneOp& outOp, uint64_t& outImm)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
                if (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64)
                    return false;
                outOp  = op == MicroOp::Add ? LaneOp::Add : op == MicroOp::Subtract ? LaneOp::Sub
                                                        : op == MicroOp::And        ? LaneOp::And
                                                        : op == MicroOp::Or         ? LaneOp::Or
                                                                                    : LaneOp::Xor;
                outImm = imm & 0xFFFFFFFFull;
                return true;

            case MicroOp::ShiftLeft:
                // The low 32 bits of a wider left shift are the 32-bit shift.
                if ((opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64) || imm >= 32)
                    return false;
                outOp  = LaneOp::ShiftLeft;
                outImm = imm;
                return true;

            case MicroOp::ShiftRight:
                // A wider right shift pulls bits above the lane into it, so
                // only the exact 32-bit form is a lane operation.
                if (opBits != MicroOpBits::B32 || imm >= 32)
                    return false;
                outOp  = LaneOp::ShiftRight;
                outImm = imm;
                return true;

            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
                if (opBits != MicroOpBits::B32 || imm == 0 || imm >= 32)
                    return false;
                outOp  = LaneOp::RotateLeft;
                outImm = op == MicroOp::RotateLeft ? imm : 32 - imm;
                return true;

            default:
                return false;
        }
    }

    // ------------------------------------------------------------------
    // Vector plan

    struct TupleKey
    {
        std::array<uint32_t, K_LANE_COUNT> ids{};

        bool     operator==(const TupleKey& other) const { return ids == other.ids; }
        uint64_t hash() const
        {
            uint64_t h = 1469598103934665603ull;
            for (const uint32_t id : ids)
            {
                h ^= id;
                h *= 1099511628211ull;
            }
            return h;
        }
    };

    struct TupleKeyHash
    {
        size_t operator()(const TupleKey& k) const { return k.hash(); }
    };

    struct VectorPlan
    {
        std::vector<PlanInstr> loads;
        std::vector<PlanInstr> ops;
        std::vector<PlanInstr> stores;

        uint32_t nextPlanReg   = 0;
        uint32_t arithmeticOps = 0;

        std::unordered_map<TupleKey, uint32_t, TupleKeyHash> tupleRegs;
        // Sorted-id key -> tuples already materialized, for permutation reuse.
        std::unordered_map<TupleKey, std::vector<TupleKey>, TupleKeyHash> tuplesBySortedKey;

        size_t totalInstrs() const { return loads.size() + ops.size() + stores.size(); }
    };

    TupleKey sortedKeyOf(const TupleKey& key)
    {
        TupleKey sorted = key;
        std::ranges::sort(sorted.ids);
        return sorted;
    }

    // pshufd control: destination lane i takes source lane control[2i+1:2i].
    bool shuffleControlFor(const TupleKey& target, const TupleKey& source, uint8_t& outControl)
    {
        uint8_t control = 0;
        for (uint32_t lane = 0; lane < K_LANE_COUNT; ++lane)
        {
            uint32_t sourceLane = K_INVALID_ID;
            for (uint32_t j = 0; j < K_LANE_COUNT; ++j)
            {
                if (source.ids[j] == target.ids[lane])
                {
                    sourceLane = j;
                    break;
                }
            }
            if (sourceLane == K_INVALID_ID)
                return false;
            control |= static_cast<uint8_t>(sourceLane << (2 * lane));
        }
        outControl = control;
        return true;
    }

    class TreeBuilder
    {
    public:
        TreeBuilder(SlpFunctionContext& fn, BlockScan& scan, VectorPlan& plan, bool nonDestructive) :
            fn_(fn),
            scan_(scan),
            plan_(plan),
            nonDestructive_(nonDestructive)
        {
        }

        // Returns the plan register holding the vector whose lane i is
        // tuple.ids[i], or K_INVALID_ID when the tuple cannot be vectorized.
        uint32_t build(const TupleKey& tuple, uint32_t depth)
        {
            if (depth > K_MAX_TREE_DEPTH || plan_.totalInstrs() > K_MAX_PLAN_INSTRS)
                return K_INVALID_ID;

            const auto memoIt = plan_.tupleRegs.find(tuple);
            if (memoIt != plan_.tupleRegs.end())
                return memoIt->second;

            // A permutation of an already-built tuple is one shuffle.
            const TupleKey sorted = sortedKeyOf(tuple);
            const auto     permIt = plan_.tuplesBySortedKey.find(sorted);
            if (permIt != plan_.tuplesBySortedKey.end())
            {
                for (const TupleKey& candidate : permIt->second)
                {
                    uint8_t control = 0;
                    if (!shuffleControlFor(tuple, candidate, control))
                        continue;
                    const uint32_t srcReg = plan_.tupleRegs.at(candidate);
                    const uint32_t dstReg = allocReg();
                    plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::Shuffle, .dst = dstReg, .src = srcReg, .imm = control});
                    remember(tuple, dstReg);
                    return dstReg;
                }
            }

            const SlpValue& n0 = scan_.values.get(tuple.ids[0]);
            const SlpValue& n1 = scan_.values.get(tuple.ids[1]);
            const SlpValue& n2 = scan_.values.get(tuple.ids[2]);
            const SlpValue& n3 = scan_.values.get(tuple.ids[3]);
            if (n0.kind != n1.kind || n0.kind != n2.kind || n0.kind != n3.kind)
                return K_INVALID_ID;

            switch (n0.kind)
            {
                case SlpValueKind::Load:
                    return buildLoad(tuple, n0, n1, n2, n3);

                case SlpValueKind::BinaryRegReg:
                {
                    if (n0.op != n1.op || n0.op != n2.op || n0.op != n3.op)
                        return K_INVALID_ID;

                    const TupleKey lhs{{n0.lhs, n1.lhs, n2.lhs, n3.lhs}};
                    const TupleKey rhs{{n0.rhs, n1.rhs, n2.rhs, n3.rhs}};

                    const uint32_t lhsReg = build(lhs, depth + 1);
                    if (lhsReg == K_INVALID_ID)
                        return K_INVALID_ID;
                    const uint32_t rhsReg = build(rhs, depth + 1);
                    if (rhsReg == K_INVALID_ID)
                        return K_INVALID_ID;

                    auto vecOp = MicroOp::VecXor;
                    switch (n0.op)
                    {
                        case LaneOp::Add:
                            vecOp = MicroOp::VecAdd32;
                            break;
                        case LaneOp::Sub:
                            vecOp = MicroOp::VecSub32;
                            break;
                        case LaneOp::And:
                            vecOp = MicroOp::VecAnd;
                            break;
                        case LaneOp::Or:
                            vecOp = MicroOp::VecOr;
                            break;
                        case LaneOp::Xor:
                            vecOp = MicroOp::VecXor;
                            break;
                        default:
                            return K_INVALID_ID;
                    }

                    const uint32_t dstReg = allocReg();
                    if (nonDestructive_)
                    {
                        plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::BinaryRegRegReg, .dst = dstReg, .src = lhsReg, .src2 = rhsReg, .op = vecOp});
                    }
                    else
                    {
                        plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::Copy, .dst = dstReg, .src = lhsReg});
                        plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::BinaryRegReg, .dst = dstReg, .src = rhsReg, .op = vecOp});
                    }
                    plan_.arithmeticOps++;
                    remember(tuple, dstReg);
                    return dstReg;
                }

                case SlpValueKind::BinaryRegImm:
                {
                    if (n0.op != n1.op || n0.op != n2.op || n0.op != n3.op)
                        return K_INVALID_ID;
                    if (n0.imm != n1.imm || n0.imm != n2.imm || n0.imm != n3.imm)
                        return K_INVALID_ID;

                    const TupleKey lhs{{n0.lhs, n1.lhs, n2.lhs, n3.lhs}};
                    const uint32_t lhsReg = build(lhs, depth + 1);
                    if (lhsReg == K_INVALID_ID)
                        return K_INVALID_ID;

                    switch (n0.op)
                    {
                        case LaneOp::ShiftLeft:
                        case LaneOp::ShiftRight:
                        {
                            const MicroOp  shiftOp = n0.op == LaneOp::ShiftLeft ? MicroOp::VecShiftLeft32 : MicroOp::VecShiftRight32;
                            const uint32_t dstReg  = allocReg();
                            emitShift(dstReg, lhsReg, shiftOp, n0.imm);
                            plan_.arithmeticOps++;
                            remember(tuple, dstReg);
                            return dstReg;
                        }

                        case LaneOp::RotateLeft:
                        {
                            // rol k == (x << k) | (x >> (32 - k)). Both halves
                            // read the same source, which is exactly the shape
                            // a destructive shift cannot express without a
                            // copy - and the copy the register allocator was
                            // giving a stack home rather than a register.
                            const uint32_t leftReg  = allocReg();
                            const uint32_t rightReg = allocReg();
                            emitShift(leftReg, lhsReg, MicroOp::VecShiftLeft32, n0.imm);
                            emitShift(rightReg, lhsReg, MicroOp::VecShiftRight32, 32 - n0.imm);
                            if (nonDestructive_)
                            {
                                const uint32_t orReg = allocReg();
                                plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::BinaryRegRegReg, .dst = orReg, .src = leftReg, .src2 = rightReg, .op = MicroOp::VecOr});
                                plan_.arithmeticOps += 3;
                                remember(tuple, orReg);
                                return orReg;
                            }
                            plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::BinaryRegReg, .dst = leftReg, .src = rightReg, .op = MicroOp::VecOr});
                            plan_.arithmeticOps += 3;
                            remember(tuple, leftReg);
                            return leftReg;
                        }

                        default:
                            // Splat immediates would need a materialized
                            // vector constant; not supported yet.
                            return K_INVALID_ID;
                    }
                }

                case SlpValueKind::Const:
                case SlpValueKind::Opaque:
                    return K_INVALID_ID;
            }

            return K_INVALID_ID;
        }

    private:
        uint32_t allocReg() const { return plan_.nextPlanReg++; }

        // A shift by an immediate, in whichever form the target offers.
        void emitShift(uint32_t dstReg, uint32_t srcReg, MicroOp shiftOp, uint64_t imm) const
        {
            if (nonDestructive_)
            {
                plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::BinaryRegRegImm, .dst = dstReg, .src = srcReg, .op = shiftOp, .imm = imm});
                return;
            }
            plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::Copy, .dst = dstReg, .src = srcReg});
            plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::BinaryRegImm, .dst = dstReg, .op = shiftOp, .imm = imm});
        }

        void remember(const TupleKey& tuple, uint32_t reg) const
        {
            plan_.tupleRegs.emplace(tuple, reg);
            plan_.tuplesBySortedKey[sortedKeyOf(tuple)].push_back(tuple);
        }

        uint32_t buildLoad(const TupleKey& tuple, const SlpValue& n0, const SlpValue& n1, const SlpValue& n2, const SlpValue& n3) const
        {
            // Four loads of block-entry memory covering one contiguous chunk,
            // in any lane order.
            if (n0.loadEpoch != 0 || n1.loadEpoch != 0 || n2.loadEpoch != 0 || n3.loadEpoch != 0)
                return K_INVALID_ID;
            if (n0.loadRootKey != n1.loadRootKey || n0.loadRootKey != n2.loadRootKey || n0.loadRootKey != n3.loadRootKey)
                return K_INVALID_ID;

            const std::array                   offsets = {n0.loadOffset, n1.loadOffset, n2.loadOffset, n3.loadOffset};
            std::array<uint64_t, K_LANE_COUNT> sorted  = offsets;
            std::ranges::sort(sorted);
            for (uint32_t lane = 1; lane < K_LANE_COUNT; ++lane)
            {
                if (sorted[lane] != sorted[0] + lane * K_LANE_BYTES)
                    return K_INVALID_ID;
            }

            // Build (or reuse) the straight in-memory-order tuple first, so
            // every permutation of the same chunk shares one packed load.
            TupleKey straight;
            for (uint32_t lane = 0; lane < K_LANE_COUNT; ++lane)
            {
                SlpValue v;
                v.kind             = SlpValueKind::Load;
                v.loadRootKey      = n0.loadRootKey;
                v.loadOffset       = sorted[0] + lane * K_LANE_BYTES;
                v.loadEpoch        = 0;
                straight.ids[lane] = scan_.values.intern(v);
            }

            uint32_t   straightReg = K_INVALID_ID;
            const auto straightIt  = plan_.tupleRegs.find(straight);
            if (straightIt != plan_.tupleRegs.end())
            {
                straightReg = straightIt->second;
            }
            else
            {
                straightReg = allocReg();
                plan_.loads.push_back(PlanInstr{.kind = PlanInstr::Kind::LoadVec, .dst = straightReg, .rootKey = n0.loadRootKey, .baseOffset = sorted[0]});
                remember(straight, straightReg);
            }

            if (straight == tuple)
                return straightReg;

            uint8_t control = 0;
            if (!shuffleControlFor(tuple, straight, control))
                return K_INVALID_ID;

            const uint32_t dstReg = allocReg();
            plan_.ops.push_back(PlanInstr{.kind = PlanInstr::Kind::Shuffle, .dst = dstReg, .src = straightReg, .imm = control});
            remember(tuple, dstReg);
            return dstReg;
        }

        SlpFunctionContext& fn_;
        BlockScan&          scan_;
        VectorPlan&         plan_;
        bool                nonDestructive_ = false;
    };

    // ------------------------------------------------------------------
    // Deletion-safety: is this SSA value dead once the deleted stores are
    // gone? Phis, side effects, surviving stores, and instructions whose CPU
    // flags may be observed all pin the value alive.

    class DeletionOracle
    {
    public:
        DeletionOracle(SlpFunctionContext& fn, const std::unordered_set<uint32_t>& deletedStoreRefs) :
            fn_(fn),
            deletedStoreRefs_(deletedStoreRefs)
        {
        }

        bool isValueDead(uint32_t valueId)
        {
            const auto it = states_.find(valueId);
            if (it != states_.end())
                return it->second != State::Live;

            // Optimistic for cycles: SSA values without phis cannot cycle, and
            // phi uses are rejected outright below.
            states_[valueId] = State::InProgress;

            const MicroSsaState::ValueInfo* info = fn_.ssa->valueInfo(valueId);
            if (!info)
            {
                states_[valueId] = State::Live;
                return false;
            }

            for (const MicroSsaState::UseSite& use : info->uses)
            {
                if (use.kind == MicroSsaState::UseSite::Kind::Phi)
                {
                    // A phi input is only a real use if the phi's result is.
                    // Loop headers carry phis for every re-defined register,
                    // including scratch values nothing reads on the next
                    // iteration; the recursion is optimistic on phi cycles,
                    // which is exact when no external use pins them.
                    const MicroSsaState::PhiInfo* phi = fn_.ssa->phiInfo(use.phiIndex);
                    if (!phi || phi->resultValueId == MicroSsaState::K_INVALID_VALUE || !isValueDead(phi->resultValueId))
                    {
                        states_[valueId] = State::Live;
                        return false;
                    }
                    continue;
                }

                if (deletedStoreRefs_.contains(use.instRef.get()))
                    continue;

                if (!isInstructionDead(use.instRef))
                {
                    states_[valueId] = State::Live;
                    return false;
                }
            }

            states_[valueId] = State::Dead;
            return true;
        }

        bool isInstructionDead(MicroInstrRef instRef)
        {
            const MicroInstr* inst = fn_.storage->ptr(instRef);
            if (!inst)
                return false;

            const MicroInstrDef& info = MicroInstr::info(inst->op);
            if (inst->op == MicroInstrOpcode::Label ||
                info.flags.has(MicroInstrFlagsE::WritesMemory) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction))
            {
                return false;
            }

            if (info.flags.has(MicroInstrFlagsE::DefinesCpuFlags) &&
                !MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(*fn_.storage, *fn_.operands, instRef))
            {
                return false;
            }

            const MicroInstrUseDef useDef = inst->collectUseDef(*fn_.operands, fn_.encoder);
            if (useDef.defs.empty())
                return false;

            for (const MicroReg defReg : useDef.defs)
            {
                uint32_t defValueId = MicroSsaState::K_INVALID_VALUE;
                if (!fn_.ssa->defValue(defReg, instRef, defValueId))
                    return false;
                if (!isValueDead(defValueId))
                    return false;
            }

            return true;
        }

    private:
        enum class State : uint8_t
        {
            InProgress,
            Dead,
            Live,
        };

        SlpFunctionContext&                 fn_;
        const std::unordered_set<uint32_t>& deletedStoreRefs_;
        std::unordered_map<uint32_t, State> states_;
    };

    // ------------------------------------------------------------------
    // Block scan

    void scanInstruction(SlpFunctionContext& fn, BlockScan& scan, const BlockInstr& blockInstr)
    {
        MicroInstr&              inst = *blockInstr.inst;
        const MicroInstrOperand* ops  = inst.ops(*fn.operands);

        switch (inst.op)
        {
            case MicroInstrOpcode::Nop:
            case MicroInstrOpcode::Breakpoint:
            case MicroInstrOpcode::SanityInvalidate:
            case MicroInstrOpcode::SanityUndefined:
            case MicroInstrOpcode::CmpRegReg:
            case MicroInstrOpcode::CmpRegImm:
                return;

            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                if (isLaneTransparentCopy(inst, ops))
                {
                    setValue(scan, ops[0].reg, currentValue(scan, ops[1].reg));
                    return;
                }
                setOpaque(scan, ops[0].reg);
                return;

            case MicroInstrOpcode::LoadRegImm:
            {
                SlpValue v;
                v.kind = SlpValueKind::Const;
                v.imm  = ops[2].valueU64 & 0xFFFFFFFFull;
                setValue(scan, ops[0].reg, scan.values.intern(v));
                return;
            }

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadVecRegMem:
            {
                const bool        isPlainLoad = inst.op == MicroInstrOpcode::LoadRegMem;
                const bool        isZeroExt   = inst.op == MicroInstrOpcode::LoadZeroExtRegMem;
                const MicroReg    baseReg     = ops[1].reg;
                const uint64_t    offsetIndex = isPlainLoad || inst.op == MicroInstrOpcode::LoadVecRegMem ? 3 : 4;
                const MicroOpBits sizeBits    = isPlainLoad || inst.op == MicroInstrOpcode::LoadVecRegMem ? ops[2].opBits : ops[3].opBits;

                if (baseReg.isInstructionPointer())
                {
                    scan.hasUnresolvedMemRead = true;
                    setOpaque(scan, ops[0].reg);
                    return;
                }

                uint64_t offset  = ops[offsetIndex].valueU64;
                uint32_t rootKey = K_INVALID_ID;
                if (!resolveRoot(fn, baseReg, offset, rootKey))
                {
                    scan.hasUnresolvedMemRead = true;
                    setOpaque(scan, ops[0].reg);
                    return;
                }

                const uint32_t size = std::max<uint32_t>(getNumBytes(sizeBits), 1);
                scan.loads.push_back(LoadRecord{.instRef = blockInstr.instRef, .pos = blockInstr.pos, .rootKey = rootKey, .offset = offset, .size = size, .dstReg = ops[0].reg});

                // Only aligned 32-bit reads become lane values; a 64<-32
                // zero-extending load preserves the lane too.
                const bool laneRead = (isPlainLoad && sizeBits == MicroOpBits::B32) ||
                                      (isZeroExt && sizeBits == MicroOpBits::B32 && ops[2].opBits == MicroOpBits::B64);
                if (!laneRead || (offset % K_LANE_BYTES) != 0)
                {
                    setOpaque(scan, ops[0].reg);
                    return;
                }

                MemLocation& loc = scan.locations[BlockScan::locationKey(rootKey, offset)];
                if (loc.valueId != K_INVALID_ID)
                {
                    setValue(scan, ops[0].reg, loc.valueId);
                    return;
                }

                SlpValue v;
                v.kind            = SlpValueKind::Load;
                v.loadRootKey     = rootKey;
                v.loadOffset      = offset;
                v.loadEpoch       = loc.epoch;
                const uint32_t id = scan.values.intern(v);
                loc.valueId       = id;
                setValue(scan, ops[0].reg, id);
                return;
            }

            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::LoadMemImm:
            case MicroInstrOpcode::StoreVecMemReg:
            {
                const bool        isRegStore  = inst.op == MicroInstrOpcode::LoadMemReg || inst.op == MicroInstrOpcode::StoreVecMemReg;
                const MicroReg    baseReg     = ops[0].reg;
                const uint64_t    offsetIndex = inst.op == MicroInstrOpcode::LoadMemImm ? 2 : 3;
                const MicroOpBits sizeBits    = inst.op == MicroInstrOpcode::LoadMemImm ? ops[1].opBits : ops[2].opBits;

                if (baseReg.isInstructionPointer())
                {
                    scan.hasUnresolvedMemWrite = true;
                    return;
                }

                uint64_t offset  = ops[offsetIndex].valueU64;
                uint32_t rootKey = K_INVALID_ID;
                if (!resolveRoot(fn, baseReg, offset, rootKey))
                {
                    scan.hasUnresolvedMemWrite = true;
                    return;
                }

                const uint32_t size    = std::max<uint32_t>(getNumBytes(sizeBits), 1);
                const bool     plain32 = inst.op != MicroInstrOpcode::StoreVecMemReg && sizeBits == MicroOpBits::B32 && (offset % K_LANE_BYTES) == 0;
                scan.stores.push_back(StoreRecord{.instRef = blockInstr.instRef, .pos = blockInstr.pos, .rootKey = rootKey, .offset = offset, .size = size, .plain32 = plain32});

                if (!plain32)
                {
                    killLocationRange(scan, rootKey, offset, size, blockInstr.instRef);
                    return;
                }

                uint32_t valueId = K_INVALID_ID;
                if (isRegStore)
                {
                    valueId = currentValue(scan, ops[1].reg);
                }
                else
                {
                    SlpValue v;
                    v.kind  = SlpValueKind::Const;
                    v.imm   = ops[3].valueU64 & 0xFFFFFFFFull;
                    valueId = scan.values.intern(v);
                }

                MemLocation& loc  = scan.locations[BlockScan::locationKey(rootKey, offset)];
                loc.valueId       = valueId;
                loc.lastIsPlain32 = true;
                loc.lastStoreRef  = blockInstr.instRef;
                return;
            }

            case MicroInstrOpcode::CmpMemReg:
            case MicroInstrOpcode::CmpMemImm:
            {
                const MicroReg    baseReg  = ops[0].reg;
                const bool        isReg    = inst.op == MicroInstrOpcode::CmpMemReg;
                const MicroOpBits sizeBits = isReg ? ops[2].opBits : ops[1].opBits;

                uint64_t offset  = isReg ? ops[3].valueU64 : ops[2].valueU64;
                uint32_t rootKey = K_INVALID_ID;
                if (baseReg.isInstructionPointer() || !resolveRoot(fn, baseReg, offset, rootKey))
                {
                    scan.hasUnresolvedMemRead = true;
                    return;
                }

                const uint32_t size = std::max<uint32_t>(getNumBytes(sizeBits), 1);
                scan.loads.push_back(LoadRecord{.instRef = blockInstr.instRef, .pos = blockInstr.pos, .rootKey = rootKey, .offset = offset, .size = size, .dstReg = MicroReg::invalid()});
                return;
            }

            case MicroInstrOpcode::OpBinaryRegReg:
            {
                LaneOp laneOp{};
                if (laneOpForBinaryRegReg(ops[3].microOp, ops[2].opBits, laneOp))
                {
                    SlpValue v;
                    v.kind = SlpValueKind::BinaryRegReg;
                    v.op   = laneOp;
                    v.lhs  = currentValue(scan, ops[0].reg);
                    v.rhs  = currentValue(scan, ops[1].reg);
                    setValue(scan, ops[0].reg, scan.values.intern(v));
                    return;
                }
                setDefsOpaque(fn, scan, inst);
                return;
            }

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                LaneOp   laneOp{};
                uint64_t laneImm = 0;
                if (laneOpForBinaryRegImm(ops[2].microOp, ops[1].opBits, ops[3].valueU64, laneOp, laneImm))
                {
                    SlpValue v;
                    v.kind = SlpValueKind::BinaryRegImm;
                    v.op   = laneOp;
                    v.lhs  = currentValue(scan, ops[0].reg);
                    v.imm  = laneImm;
                    setValue(scan, ops[0].reg, scan.values.intern(v));
                    return;
                }
                setDefsOpaque(fn, scan, inst);
                return;
            }

            case MicroInstrOpcode::OpBinaryRegMem:
            {
                // Register op= memory: a read that must be tracked like a
                // load, folded into the destination's lane value when the
                // operation and width allow it.
                const MicroReg baseReg = ops[1].reg;
                uint64_t       offset  = ops[4].valueU64;
                uint32_t       rootKey = K_INVALID_ID;
                if (baseReg.isInstructionPointer() || !resolveRoot(fn, baseReg, offset, rootKey))
                {
                    scan.hasUnresolvedMemRead = true;
                    setOpaque(scan, ops[0].reg);
                    return;
                }

                const uint32_t size = std::max<uint32_t>(getNumBytes(ops[2].opBits), 1);
                scan.loads.push_back(LoadRecord{.instRef = blockInstr.instRef, .pos = blockInstr.pos, .rootKey = rootKey, .offset = offset, .size = size, .dstReg = ops[0].reg});

                LaneOp laneOp{};
                if (!laneOpForBinaryRegReg(ops[3].microOp, ops[2].opBits, laneOp) ||
                    ops[2].opBits != MicroOpBits::B32 || (offset % K_LANE_BYTES) != 0)
                {
                    setOpaque(scan, ops[0].reg);
                    return;
                }

                MemLocation& loc         = scan.locations[BlockScan::locationKey(rootKey, offset)];
                uint32_t     loadedValue = loc.valueId;
                if (loadedValue == K_INVALID_ID)
                {
                    SlpValue v;
                    v.kind        = SlpValueKind::Load;
                    v.loadRootKey = rootKey;
                    v.loadOffset  = offset;
                    v.loadEpoch   = loc.epoch;
                    loadedValue   = scan.values.intern(v);
                    loc.valueId   = loadedValue;
                }

                SlpValue v;
                v.kind = SlpValueKind::BinaryRegReg;
                v.op   = laneOp;
                v.lhs  = currentValue(scan, ops[0].reg);
                v.rhs  = loadedValue;
                setValue(scan, ops[0].reg, scan.values.intern(v));
                return;
            }

            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
            case MicroInstrOpcode::OpUnaryMem:
            {
                const MicroReg    baseReg  = ops[0].reg;
                uint64_t          offset   = inst.op == MicroInstrOpcode::OpBinaryMemReg ? ops[4].valueU64 : ops[3].valueU64;
                const MicroOpBits sizeBits = inst.op == MicroInstrOpcode::OpBinaryMemReg ? ops[2].opBits : ops[1].opBits;

                uint32_t rootKey = K_INVALID_ID;
                if (baseReg.isInstructionPointer() || !resolveRoot(fn, baseReg, offset, rootKey))
                {
                    scan.hasUnresolvedMemRead  = true;
                    scan.hasUnresolvedMemWrite = true;
                    return;
                }

                // Read-modify-write on a resolvable location: record both
                // sides and drop the known value.
                const uint32_t size = std::max<uint32_t>(getNumBytes(sizeBits), 1);
                scan.loads.push_back(LoadRecord{.instRef = blockInstr.instRef, .pos = blockInstr.pos, .rootKey = rootKey, .offset = offset, .size = size, .dstReg = MicroReg::invalid()});
                scan.stores.push_back(StoreRecord{.instRef = blockInstr.instRef, .pos = blockInstr.pos, .rootKey = rootKey, .offset = offset, .size = size, .plain32 = false});
                killLocationRange(scan, rootKey, offset, size, blockInstr.instRef);
                return;
            }

            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::Pop:
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
                scan.hasUnresolvedMemWrite = true;
                setDefsOpaque(fn, scan, inst);
                return;

            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadSignedExtAmcRegMem:
            case MicroInstrOpcode::LoadZeroExtAmcRegMem:
            case MicroInstrOpcode::CmpAmcImm:
                scan.hasUnresolvedMemRead = true;
                setDefsOpaque(fn, scan, inst);
                return;

            default:
                setDefsOpaque(fn, scan, inst);
        }
    }

    // ------------------------------------------------------------------

    struct SeedGroup
    {
        uint32_t rootKey = K_INVALID_ID;
        uint64_t offset  = 0;
        TupleKey tuple;
        uint32_t planReg = K_INVALID_ID;
    };

    // True when no live CPU flags cross the insertion point: scanning forward
    // from it, a flag definition must come before any flag use or control
    // transfer.
    bool flagsDeadAtInsertion(const SlpFunctionContext& fn, MicroInstrRef insertBeforeRef)
    {
        for (MicroInstrRef scanRef = insertBeforeRef; scanRef.isValid(); scanRef = fn.storage->findNextInstructionRef(scanRef))
        {
            const MicroInstr* inst = fn.storage->ptr(scanRef);
            if (!inst)
                return false;

            const MicroInstrOperand* ops = inst->ops(*fn.operands);
            if (MicroPassHelpers::instructionActuallyUsesCpuFlags(*inst, ops))
                return false;

            const MicroInstrDef& info = MicroInstr::info(inst->op);
            if (inst->op == MicroInstrOpcode::Label ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction))
            {
                return false;
            }

            if (info.flags.has(MicroInstrFlagsE::DefinesCpuFlags))
                return true;
        }

        return false;
    }

    bool vectorizeBlock(SlpFunctionContext& fn, std::span<const BlockInstr> blockInstrs)
    {
        if (blockInstrs.size() < K_LANE_COUNT * 2)
            return false;

        BlockScan scan;
        for (const BlockInstr& blockInstr : blockInstrs)
            scanInstruction(fn, scan, blockInstr);

        if (scan.stores.empty())
            return false;

        // Candidate locations: final write is a plain aligned 32-bit store and
        // nothing ever wrote the location any other way.
        struct Candidate
        {
            uint64_t      offset  = 0;
            uint32_t      valueId = K_INVALID_ID;
            MicroInstrRef lastStoreRef;
        };
        std::unordered_map<uint32_t, std::vector<Candidate>> candidatesByRoot;
        for (const auto& [key, loc] : scan.locations)
        {
            if (!loc.lastIsPlain32 || loc.hasNonPlainStore || loc.valueId == K_INVALID_ID)
                continue;
            const auto rootKey = static_cast<uint32_t>(key >> 40);
            const auto offset  = key ^ (static_cast<uint64_t>(rootKey) << 40);
            candidatesByRoot[rootKey].push_back(Candidate{.offset = offset, .valueId = loc.valueId, .lastStoreRef = loc.lastStoreRef});
        }

        if (candidatesByRoot.empty())
            return false;

        // Aliasing policy. Every memory access in the block must have
        // resolved to a root, and the roots the block touches must be
        // provably disjoint: a single root, or the stack pointer paired with
        // one incoming parameter. The frame a function executes in did not
        // exist when its caller formed the pointer it passed, so an argument
        // cannot address it - which is why a parameter is the only foreign
        // root ever paired with the frame. Two roots of unknown provenance
        // are never assumed disjoint.
        if (scan.hasUnresolvedMemRead || scan.hasUnresolvedMemWrite)
            return false;

        std::unordered_set<uint32_t> touchedRoots;
        for (const StoreRecord& record : scan.stores)
            touchedRoots.insert(record.rootKey);
        for (const LoadRecord& record : scan.loads)
            touchedRoots.insert(record.rootKey);

        if (touchedRoots.size() > 2)
            return false;
        if (touchedRoots.size() == 2)
        {
            bool hasStack     = false;
            bool hasParameter = false;
            for (const uint32_t rootKey : touchedRoots)
            {
                hasStack     = hasStack || fn.roots[rootKey].kind == RootKind::StackPointer;
                hasParameter = hasParameter || fn.roots[rootKey].kind == RootKind::Parameter;
            }
            if (!hasStack || !hasParameter)
                return false;
        }

        // Build the seed groups: complete 16-byte chunks of candidates.
        VectorPlan             plan;
        TreeBuilder            builder(fn, scan, plan, fn.encoder && fn.encoder->supportsNonDestructiveFloatBinary());
        std::vector<SeedGroup> groups;

        for (auto& [rootKey, candidates] : candidatesByRoot)
        {
            std::ranges::sort(candidates, [](const Candidate& a, const Candidate& b) { return a.offset < b.offset; });

            size_t index = 0;
            while (index + K_LANE_COUNT <= candidates.size())
            {
                bool contiguous = true;
                for (uint32_t lane = 1; lane < K_LANE_COUNT; ++lane)
                {
                    if (candidates[index + lane].offset != candidates[index].offset + lane * K_LANE_BYTES)
                    {
                        contiguous = false;
                        break;
                    }
                }

                if (!contiguous)
                {
                    index++;
                    continue;
                }

                SeedGroup group;
                group.rootKey = rootKey;
                group.offset  = candidates[index].offset;
                for (uint32_t lane = 0; lane < K_LANE_COUNT; ++lane)
                    group.tuple.ids[lane] = candidates[index + lane].valueId;
                groups.push_back(group);
                index += K_LANE_COUNT;
            }
        }

        if (groups.empty())
            return false;

        // Grow the trees; a group that fails simply keeps its scalar stores.
        std::vector<SeedGroup> vectorized;
        for (SeedGroup& group : groups)
        {
            group.planReg = builder.build(group.tuple, 0);
            if (group.planReg != K_INVALID_ID)
                vectorized.push_back(group);
        }

        if (vectorized.empty() || plan.arithmeticOps == 0)
            return false;

        // The deleted set: every plain 32-bit store to a vectorized location.
        std::unordered_set<uint64_t> vectorizedLocations;
        for (const SeedGroup& group : vectorized)
        {
            for (uint32_t lane = 0; lane < K_LANE_COUNT; ++lane)
                vectorizedLocations.insert(BlockScan::locationKey(group.rootKey, group.offset + lane * K_LANE_BYTES));
        }

        std::unordered_set<uint32_t> deletedStoreRefs;
        uint32_t                     firstDeletedPos = K_INVALID_ID;
        MicroInstrRef                firstDeletedRef = MicroInstrRef::invalid();
        for (const StoreRecord& record : scan.stores)
        {
            if (!record.plain32 || !vectorizedLocations.contains(BlockScan::locationKey(record.rootKey, record.offset)))
                continue;
            deletedStoreRefs.insert(record.instRef.get());
            if (record.pos < firstDeletedPos)
            {
                firstDeletedPos = record.pos;
                firstDeletedRef = record.instRef;
            }
        }

        SWC_ASSERT(!deletedStoreRefs.empty() && firstDeletedRef.isValid());

        const auto overlapsVectorized = [&](const uint32_t rootKey, const uint64_t offset, const uint32_t size) {
            const uint64_t first = offset & ~static_cast<uint64_t>(K_LANE_BYTES - 1);
            for (uint64_t o = first; o < offset + size; o += K_LANE_BYTES)
            {
                if (vectorizedLocations.contains(BlockScan::locationKey(rootKey, o)))
                    return true;
            }
            return false;
        };

        // Packed leaf loads run at the insertion point and must observe
        // block-entry memory: no surviving store may precede them into any
        // location they read.
        for (const PlanInstr& load : plan.loads)
        {
            for (const StoreRecord& record : scan.stores)
            {
                if (record.pos >= firstDeletedPos || deletedStoreRefs.contains(record.instRef.get()))
                    continue;
                if (record.rootKey != load.rootKey)
                    continue;
                if (record.offset < load.baseOffset + K_CHUNK_BYTES && load.baseOffset < record.offset + record.size)
                    return false;
            }
        }

        // Deleting a store is only sound when every later read of the
        // location dies with the scalar chain.
        DeletionOracle oracle(fn, deletedStoreRefs);
        for (const LoadRecord& load : scan.loads)
        {
            if (load.pos <= firstDeletedPos)
                continue;
            if (!overlapsVectorized(load.rootKey, load.offset, load.size))
                continue;
            if (!load.dstReg.isValid())
                return false;

            uint32_t valueId = MicroSsaState::K_INVALID_VALUE;
            if (!fn.ssa->defValue(load.dstReg, load.instRef, valueId))
                return false;
            if (!oracle.isValueDead(valueId))
                return false;
        }

        // Root registers referenced by the packed code must be defined before
        // the insertion point. A single-definition register used by this
        // block's memory accesses necessarily dominates the block, so the
        // only unsafe placement is a definition inside this very block at or
        // after the insertion point - checked structurally, by reference,
        // because instruction positions from the whole-function scan drift
        // once an earlier block has been rewritten.
        std::unordered_set<uint32_t> referencedRoots;
        for (const PlanInstr& load : plan.loads)
            referencedRoots.insert(load.rootKey);
        for (const SeedGroup& group : vectorized)
            referencedRoots.insert(group.rootKey);
        for (const uint32_t rootKey : referencedRoots)
        {
            const RootInfo& root = fn.roots[rootKey];
            if (!root.reg.isVirtual())
                continue;
            const auto defIt = fn.regDefs.find(root.reg.packed);
            if (defIt == fn.regDefs.end())
                continue;
            for (const BlockInstr& blockInstr : blockInstrs)
            {
                if (blockInstr.instRef == defIt->second.defRef && blockInstr.pos >= firstDeletedPos)
                    return false;
            }
        }

        // The packed sequence writes CPU flags, so no live flags may cross
        // the insertion point.
        if (!flagsDeadAtInsertion(fn, firstDeletedRef))
            return false;

        // ----- Materialize.
        std::vector<MicroReg> planRegs(plan.nextPlanReg);
        for (uint32_t planReg = 0; planReg < plan.nextPlanReg; ++planReg)
        {
            SWC_ASSERT(fn.nextVirtualFloatRegIndex < MicroReg::K_MAX_INDEX);
            planRegs[planReg] = MicroReg::virtualFloatReg(fn.nextVirtualFloatRegIndex++);
        }

        const auto emitPlanInstr = [&](const PlanInstr& planInstr) {
            switch (planInstr.kind)
            {
                case PlanInstr::Kind::LoadVec:
                {
                    std::array<MicroInstrOperand, 4> ops;
                    ops[0].reg      = planRegs[planInstr.dst];
                    ops[1].reg      = fn.roots[planInstr.rootKey].reg;
                    ops[2].opBits   = MicroOpBits::B128;
                    ops[3].valueU64 = planInstr.baseOffset;
                    fn.storage->insertDerivedBefore(*fn.operands, firstDeletedRef, MicroInstrOpcode::LoadVecRegMem, ops);
                    break;
                }
                case PlanInstr::Kind::StoreVec:
                {
                    std::array<MicroInstrOperand, 4> ops;
                    ops[0].reg      = fn.roots[planInstr.rootKey].reg;
                    ops[1].reg      = planRegs[planInstr.src];
                    ops[2].opBits   = MicroOpBits::B128;
                    ops[3].valueU64 = planInstr.baseOffset;
                    fn.storage->insertDerivedBefore(*fn.operands, firstDeletedRef, MicroInstrOpcode::StoreVecMemReg, ops);
                    break;
                }
                case PlanInstr::Kind::Copy:
                {
                    std::array<MicroInstrOperand, 3> ops;
                    ops[0].reg    = planRegs[planInstr.dst];
                    ops[1].reg    = planRegs[planInstr.src];
                    ops[2].opBits = MicroOpBits::B128;
                    fn.storage->insertDerivedBefore(*fn.operands, firstDeletedRef, MicroInstrOpcode::LoadRegReg, ops);
                    break;
                }
                case PlanInstr::Kind::BinaryRegReg:
                {
                    std::array<MicroInstrOperand, 4> ops;
                    ops[0].reg     = planRegs[planInstr.dst];
                    ops[1].reg     = planRegs[planInstr.src];
                    ops[2].opBits  = MicroOpBits::B128;
                    ops[3].microOp = planInstr.op;
                    fn.storage->insertDerivedBefore(*fn.operands, firstDeletedRef, MicroInstrOpcode::OpBinaryRegReg, ops);
                    break;
                }
                case PlanInstr::Kind::BinaryRegImm:
                {
                    std::array<MicroInstrOperand, 4> ops;
                    ops[0].reg     = planRegs[planInstr.dst];
                    ops[1].opBits  = MicroOpBits::B128;
                    ops[2].microOp = planInstr.op;
                    ops[3].setImmediateValue(ApInt(planInstr.imm, 64));
                    fn.storage->insertDerivedBefore(*fn.operands, firstDeletedRef, MicroInstrOpcode::OpBinaryRegImm, ops);
                    break;
                }
                case PlanInstr::Kind::BinaryRegRegReg:
                {
                    std::array<MicroInstrOperand, 5> ops;
                    ops[0].reg     = planRegs[planInstr.dst];
                    ops[1].reg     = planRegs[planInstr.src];
                    ops[2].reg     = planRegs[planInstr.src2];
                    ops[3].opBits  = MicroOpBits::B128;
                    ops[4].microOp = planInstr.op;
                    fn.storage->insertDerivedBefore(*fn.operands, firstDeletedRef, MicroInstrOpcode::OpBinaryRegRegReg, ops);
                    break;
                }
                case PlanInstr::Kind::BinaryRegRegImm:
                {
                    std::array<MicroInstrOperand, 5> ops;
                    ops[0].reg     = planRegs[planInstr.dst];
                    ops[1].reg     = planRegs[planInstr.src];
                    ops[2].opBits  = MicroOpBits::B128;
                    ops[3].microOp = planInstr.op;
                    ops[4].setImmediateValue(ApInt(planInstr.imm, 64));
                    fn.storage->insertDerivedBefore(*fn.operands, firstDeletedRef, MicroInstrOpcode::OpBinaryRegRegImm, ops);
                    break;
                }
                case PlanInstr::Kind::Shuffle:
                {
                    std::array<MicroInstrOperand, 4> ops;
                    ops[0].reg      = planRegs[planInstr.dst];
                    ops[1].reg      = planRegs[planInstr.src];
                    ops[2].opBits   = MicroOpBits::B128;
                    ops[3].valueU64 = planInstr.imm;
                    fn.storage->insertDerivedBefore(*fn.operands, firstDeletedRef, MicroInstrOpcode::VecShuffleRegRegImm, ops);
                    break;
                }
            }
        };

        for (const PlanInstr& planInstr : plan.loads)
            emitPlanInstr(planInstr);
        for (const PlanInstr& planInstr : plan.ops)
            emitPlanInstr(planInstr);
        for (const SeedGroup& group : vectorized)
        {
            PlanInstr store;
            store.kind       = PlanInstr::Kind::StoreVec;
            store.src        = group.planReg;
            store.rootKey    = group.rootKey;
            store.baseOffset = group.offset;
            emitPlanInstr(store);
        }

        for (const uint32_t refValue : deletedStoreRefs)
            fn.storage->erase(MicroInstrRef(refValue));

        return true;
    }
}

Result MicroSlpVectorizePass::run(MicroPassContext& context)
{
    if (!context.builder || !context.instructions || !context.operands || !context.encoder)
        return Result::Continue;

    const Runtime::BuildCfgBackend& backendCfg = context.builder->backendBuildCfg();
    if (!backendCfg.optimize || backendCfg.cpuVectorize == Runtime::BuildCfgBackendCpuVectorize::None)
        return Result::Continue;

    SlpFunctionContext fn;
    fn.context  = &context;
    fn.storage  = context.instructions;
    fn.operands = context.operands;
    fn.encoder  = context.encoder;

    // Single-definition map for address rooting, and global positions.
    std::vector<BlockInstr> blockInstrs;
    uint32_t                position = 0;
    for (auto it = fn.storage->view().begin(); it != fn.storage->view().end(); ++it, ++position)
    {
        if (fn.firstCallPos == K_INVALID_ID && MicroInstr::info(it->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
            fn.firstCallPos = position;

        const MicroInstrUseDef useDef = it->collectUseDef(*fn.operands, fn.encoder);
        for (const MicroReg reg : useDef.defs)
        {
            if (!reg.isVirtual())
                continue;
            RegDefInfo& info = fn.regDefs[reg.packed];
            info.defCount++;
            info.defRef = it.current;
            info.defPos = position;
        }
    }

    MicroSsaState        localSsa;
    const MicroSsaState* ssa = MicroSsaState::ensureFor(context, localSsa);
    if (!ssa)
        return Result::Continue;
    fn.ssa = ssa;

    fn.nextVirtualFloatRegIndex = MicroPassHelpers::computeNextVirtualFloatRegIndex(context);

    // Walk the straight-line blocks.
    bool changed = false;
    position     = 0;
    blockInstrs.clear();

    const auto flushBlock = [&]() {
        if (!blockInstrs.empty() && vectorizeBlock(fn, blockInstrs))
            changed = true;
        blockInstrs.clear();
    };

    for (auto it = fn.storage->view().begin(); it != fn.storage->view().end(); ++it, ++position)
    {
        MicroInstr&          inst = *it;
        const MicroInstrDef& info = MicroInstr::info(inst.op);

        const bool isBoundary = inst.op == MicroInstrOpcode::Label ||
                                inst.op == MicroInstrOpcode::End ||
                                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                                info.flags.has(MicroInstrFlagsE::IsCallInstruction);
        if (isBoundary)
        {
            flushBlock();
            continue;
        }

        blockInstrs.push_back(BlockInstr{.instRef = it.current, .inst = &inst, .pos = position});
    }
    flushBlock();

    if (changed)
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
