#pragma once
#include "Backend/RuntimeBackendConfig.h"

SWC_BEGIN_NAMESPACE();

// Compile-time policy for micro optimization and its shared analyses. Keep every tunable
// iteration cap, search window, recursion depth, growth budget and cost-model weight here.
// Equal defaults do not imply one policy: independently motivated limits stay independent.
//
// These defaults preserve the existing optimizer behavior. Comments describe purpose and
// exhaustion behavior, not a claim that a threshold is optimal. Revisit values with evidence.
// Runtime overrides live in BuildCfgBackendOptimizer. Fixed proof and storage bounds stay here.
//
// Role tags distinguish optional analysis work, output growth, profitability/pressure models,
// convergence guards and representation/proof-domain constraints. Larger is not generally better:
// a guard only matters when reached, growth can create spills, and exact shapes are not tunable.
// See bench/results/optimizer-policy/20261019/limits.csv for the per-constant assessment.
// An implementation recursion cap is not a proof that every supported host stack can sustain it.
//
// Instruction widths, operand positions, ABI rules, sentinels, exact pattern arities and
// inline container capacities are representation constraints, not optimizer policy. Keep
// those with their owning representation; do not turn them into tuning knobs here.
namespace MicroOptimizationLimits
{
    namespace Memory
    {
        // [growth-policy] Expand constant-size memory operations only up to this byte count when no override is supplied.
        inline constexpr uint32_t K_DEFAULT_UNROLL_MEM_LIMIT = 256;
    }

    // A zero override requests the documented default, including in value-initialized Swag configs.
    template<typename T>
    constexpr T configured(const uint32_t value, const T fallback)
    {
        return value ? static_cast<T>(value) : fallback;
    }

    namespace Pipeline
    {
        // [pipeline-contract] Allow one sweep with backend optimization disabled.
        inline constexpr uint32_t K_OPT_ITERATION_OFF = 1;

        // [mixed-convergence-and-work] Shared default for two distinct roles: a pre-RA convergence guard and an optional post-RA cleanup budget.
        inline constexpr uint32_t K_OPT_ITERATION_ON = 24;

        // [convergence-guard] Cap legalization/allocation sweeps; exhaustion reports an internal code-generation error.
        inline constexpr uint32_t K_RA_ITERATION_ON = 16;

        // [analysis-budget] Bound peephole/DCE cleanup before frame setup; later post-RA cleanup has its own budget.
        inline constexpr uint32_t K_PRE_PROLOGUE_SWEEPS = 2;
    }

    namespace Helpers
    {
        // [analysis-budget] Bound shared address-root tracing; exhaustion leaves the root unproved.
        inline constexpr uint32_t K_MAX_ROOT_CHAIN = 32;
    }

    namespace DenseRegIndex
    {
        // [storage-strategy] Use dense lookup tables only up to this register index; larger indices use the sparse map.
        inline constexpr uint32_t K_MAX_DIRECT_INDEX = 1u << 20;
    }

    namespace BranchSimplify
    {
        // [analysis-budget] Bound path exploration for a known comparison; exhaustion leaves the branch unchanged.
        inline constexpr uint32_t K_MAX_WALK = 256;

        // [analysis-budget] Bound the copy/extension chain searched before a short-circuit Boolean branch.
        inline constexpr uint32_t K_MAX_SHORT_CIRCUIT_BOOL_CHAIN = 6;

        // [analysis-budget] Bound the search for an existing branchless join before changing a predecessor.
        inline constexpr size_t K_MAX_LINK = 8;

        // [profitability-policy] Require enough equality tests to pay for materializing and testing a bitmap.
        inline constexpr uint32_t K_MIN_CHAIN = 3;

        // [analysis-budget] Bound equality-chain discovery; a single word holds the resulting bit test.
        inline constexpr uint32_t K_MAX_CHAIN = 64;

        // [profitability-policy] Limit speculative work when replacing an OR chain with unconditional Boolean computation.
        inline constexpr uint32_t K_MAX_LINKS = 4;

        // [profitability-policy] Admit only short OR-chain bodies so branch removal does not add excessive work.
        inline constexpr uint32_t K_MAX_BODY = 3;

        // [representation-invariant] Exact size of the negated three-way comparison pattern; its non-negated form has one fewer instruction.
        inline constexpr size_t K_MAX_SHAPE = 11;

        // [profitability-policy] Require enough switch cases to pay for packed-table index setup.
        inline constexpr size_t K_MIN_CASES = 3;

        // [representation-invariant] Reserve a default entry while keeping a packed-table shift inside a 64-bit word.
        inline constexpr uint64_t K_MAX_ENTRIES = 63;

        // [analysis-budget] Bound the search for a switch case value preceding its exit.
        inline constexpr size_t K_MAX_LOOKBACK = 4;

        // [analysis-budget] Bound the flag-producer search when folding a floating-point select to min/max.
        inline constexpr uint32_t K_MAX_FLAG_WINDOW = 4;

        // [profitability-policy] Limit work speculated from an untaken diamond arm during if-conversion.
        inline constexpr uint32_t K_MAX_IF_CONVERT_ARM_INSTR = 6;

        // [analysis-budget] Backstop repeated branch threading; later pipeline sweeps can continue simplification.
        inline constexpr uint32_t K_MAX_THREAD_ROUNDS = 4096;

        // [analysis-budget] Bound copy chasing when locating a Boolean definition feeding a branch.
        inline constexpr uint32_t K_MAX_BOOL_DEF_HOPS = 4;

        // [growth-policy] Limit constant-memory switch tables to contain emitted data size.
        inline constexpr uint32_t K_MAX_MEMORY_TABLE_ENTRIES = 256;

        // [analysis-budget] Bound phi-use exploration during if-conversion; exhaustion conservatively treats a value as read
        // outside.
        inline constexpr uint32_t K_MAX_OUTSIDE_USE_PHIS = 16;
    }

    namespace ConstantFolding
    {
        // [analysis-budget] Bound address-origin recursion; an unresolved origin prevents constant-load folding.
        inline constexpr uint32_t K_MAX_ADDRESS_CHAIN_DEPTH = 8;

        // [analysis-budget] Bound the constant-table scan used to prove every entry has the same comparison result.
        inline constexpr uint32_t K_MAX_UNIFORM_TABLE_ENTRIES = 256;
    }

    namespace Emit
    {
        // [target-layout] Align hot loop headers to reduce fetch/cache-line splits.
        inline constexpr uint32_t K_LOOP_HEADER_ALIGNMENT = 16;

        // [target-layout] Keep fused loop compare/branch groups away from the affected x64 fetch boundary.
        inline constexpr uint32_t K_BRANCH_BOUNDARY = 32;
    }

    namespace InductionVariable
    {
        // [analysis-budget] Bound loop rediscovery after reductions invalidate the CFG; the outer loop checks convergence.
        inline constexpr uint32_t K_MAX_LOCAL_ROUNDS = 32;
    }

    namespace InstructionCombine
    {
        // [analysis-budget] Bound SSA copy chasing shared by instruction-combine rules.
        inline constexpr uint32_t K_MAX_COPY_CHAIN = 4;
    }

    namespace InstructionCombineAddressMode
    {
        // [analysis-budget] Bound the backward search for an offset-related address index.
        inline constexpr uint32_t K_MAX_RELATED_INDEX_SCAN = 24;

        // [analysis-budget] Bound constant-stride tracing through copies before folding an address scale.
        inline constexpr uint32_t K_MAX_STRIDE_DEF_DEPTH = 2;
    }

    namespace InstructionCombineBuildVector
    {
        // [analysis-budget] Bound backward scalar construction/store searches before forming a packed vector.
        inline constexpr uint32_t K_MAX_BUILD_WINDOW = 64;

        // [profitability-policy] Charge one instruction to insert an existing scalar register into a vector.
        inline constexpr uint32_t K_REGISTER_INSERT_COST = 1;

        // [profitability-policy] Charge both scalar materialization and insertion for an immediate vector lane.
        inline constexpr uint32_t K_IMMEDIATE_INSERT_COST = 2;

        // [profitability-policy] Charge one instruction for starting a vector with a clear.
        inline constexpr uint32_t K_VECTOR_CLEAR_COST = 1;
    }

    namespace InstructionCombineCommon
    {
        // [analysis-budget] Bound address-definition tracing; exhaustion declines the address-based rewrite.
        inline constexpr uint32_t K_MAX_ADDRESS_CHAIN = 8;
    }

    namespace InstructionCombineCompare
    {
        // [analysis-budget] Bound compared-load reuse and its all-path memory proof;
        // a path leaving this region keeps the reload.
        inline constexpr uint32_t K_MAX_RELOAD_SCAN = 96;

        // [analysis-budget] Bound the distance over which a subtraction can replace a later comparison.
        inline constexpr uint32_t K_MAX_WINDOW = 6;
    }

    namespace InstructionCombineConstProp
    {
        // [analysis-budget] Bound recursive constant resolution through phi inputs; exhaustion means unknown.
        inline constexpr int K_MAX_PHI_DEPTH = 4;

        // [analysis-budget] Bound recursive range proofs; exhaustion cannot justify a constant comparison.
        inline constexpr int K_MAX_BOUND_DEPTH = 6;

        // [analysis-budget] Bound flag-consumer discovery before swapping comparison operands.
        inline constexpr uint32_t K_MAX_SWAP_FLAG_SCAN = 16;

        // [analysis-budget] Bound flag-consumer discovery before replacing a proven comparison result.
        inline constexpr uint32_t K_MAX_RESOLVED_FLAG_SCAN = 16;
    }

    namespace InstructionCombineGuard
    {
        // [analysis-budget] Bound the search for a redundant guard across otherwise safe instructions.
        inline constexpr uint32_t K_MAX_SCAN = 96;
    }

    namespace InstructionCombineLoadFold
    {
        // [analysis-budget] Bound the search for consumers into which an earlier memory load can fold.
        inline constexpr uint32_t K_MAX_LOADFOLD_WINDOW = 16;

        // [analysis-budget] Bound the search for a reusable load before reading the same memory again.
        inline constexpr uint32_t K_MAX_REREAD_WINDOW = 32;

        // [analysis-budget] Bound copy tracing before proving a repeated memory read redundant.
        inline constexpr uint32_t K_MAX_REREAD_COPY_DEPTH = 8;
    }

    namespace InstructionCombineMemoryFold
    {
        // [analysis-budget] Bound scalar memory-combining scans to keep local rule matching affordable.
        inline constexpr uint32_t K_MAX_FOLD_WINDOW = 16;

        // [analysis-budget] Allow a wider store window for packed groups assembled from multiple scalar lanes.
        inline constexpr uint32_t K_MAX_SLP_STORE_WINDOW = K_MAX_FOLD_WINDOW * 4;
    }

    namespace InstructionCombineNarrowExtend
    {
        // [analysis-budget] Bound recursive demanded-bit proofs; exhaustion preserves the wider operation.
        inline constexpr uint32_t K_MAX_DEMAND_DEPTH = 4;

        // [analysis-budget] Allow longer select chains without unbounded recursive width inference.
        inline constexpr uint32_t K_MAX_SELECT_DEPTH = 24;

        // [analysis-budget] Bound the flag-reader search before changing an extension-producing instruction.
        inline constexpr uint32_t K_MAX_FLAG_WALK = 4;
    }

    namespace InstructionCombineRegImm
    {
        // [analysis-budget] Bound single-use copy tracing from a shift back to its masking instruction.
        inline constexpr int K_MAX_MASK_COPY_DEPTH = 8;
    }

    namespace InstructionCombineRegReg
    {
        // [cost-model] Three stages beat the two-cycle serial shift/add path
        // with one multiply latency and balanced additions; shorter chains keep it.
        inline constexpr uint32_t K_MIN_AFFINE_STAGES = 3;

        // [cost-model] Three stages retain two multiplies after local lowering.
        // Longer connected chains keep their local expansions.
        inline constexpr uint32_t K_MAX_AFFINE_STAGES = 3;

        // [analysis-budget] Bound the search for a consumer that can reuse its input register in place.
        inline constexpr uint32_t K_MAX_INPLACE_WINDOW = 32;

        // [analysis-budget] Bound recursive bit-origin tracing used to recognize byte swaps.
        inline constexpr uint32_t K_MAX_BSWAP_DEPTH = 10;

        // [analysis-budget] Bound copy tracing when recovering a multiplication factor.
        inline constexpr uint32_t K_MAX_FACTOR_COPY_DEPTH = 8;

        // [analysis-budget] Bound address-copy and constant-offset normalization for packed byte loads.
        inline constexpr uint32_t K_MAX_BYTE_INDEX_DEPTH = 5;

        // [analysis-budget] Bound recursive origin proofs before fusing scalar byte loads.
        inline constexpr uint32_t K_MAX_PACKED_BYTE_DEPTH = 12;

        // [analysis-budget] Bound the straight-line backward proof that all scalar byte loads can move to the fused read.
        inline constexpr uint32_t K_MAX_PACKED_BYTE_SCAN = 64;
    }

    namespace InstructionCombineStoreToLoad
    {
        // [analysis-budget] Bound the scan proving that a store source can reuse a preceding load.
        inline constexpr uint32_t K_MAX_WINDOW = 32;
    }

    namespace InstructionCombineVecLoadFold
    {
        // [analysis-budget] Bound the instruction search for scalar memory operations that form one vector load.
        inline constexpr uint32_t K_MAX_VECFOLD_WINDOW = 512;

        // [analysis-budget] Bound recursive vector address-origin proofs; exhaustion declines the fold.
        inline constexpr uint32_t K_MAX_ORIGIN_DEPTH = 12;

        // [analysis-budget] Bound the predecessor walk used to prove block-entry memory origins.
        inline constexpr uint32_t K_MAX_ENTRY_WALK = 256;

        // [analysis-budget] Bound phi recursion while comparing vector-load origins; exhaustion means unknown.
        inline constexpr uint32_t K_MAX_COMPARE_PHI_DEPTH = 4;
    }

    namespace InstructionCombineZeroExtend
    {
        // [analysis-budget] Bound phi recursion in known-zero-bit proofs; exhaustion preserves the extension.
        inline constexpr uint32_t K_MAX_PHI_DEPTH = 8;

        // [analysis-budget] Bound copy tracing when looking for a full-width definition that clears high bits.
        inline constexpr uint32_t K_MAX_COPIES = 4;
    }

    namespace LoopInvariantCodeMotion
    {
        // [analysis-budget] Bound internal hoisting rounds; the enclosing pre-RA loop can revisit remaining invariants.
        inline constexpr uint32_t K_MAX_ROUNDS = 64;

        // [analysis-budget] Bound the definition web considered for a shared hoist to limit proof cost.
        inline constexpr size_t K_MAX_WEB_DEFS = 32;
    }

    namespace LoopLoadForward
    {
        // [analysis-budget] Skip large loop bodies rather than perform expensive memory-forwarding proofs.
        inline constexpr uint32_t K_MAX_BODY = 256;

        // [analysis-budget] Bound address-root tracing when comparing loop loads and stores.
        inline constexpr uint32_t K_MAX_ROOT_HOP = 16;
    }

    namespace LoopUnroll
    {
        // [growth-policy] Cap the configurable partial factor to contain cloned code and indexed displacement growth.
        inline constexpr uint32_t K_MAX_PARTIAL_UNROLL_FACTOR = 64;

        // [growth-policy] Cap full unrolling of ordinary counted loops to contain code growth.
        inline constexpr uint64_t K_MAX_TRIPS = 16;

        // [growth-policy] Allow larger bodies only for very short loops exposing constant-table reads.
        inline constexpr uint64_t K_MAX_WIDE_TABLE_TRIPS = 4;

        // [growth-policy] Cap the original body size for the constant-table unrolling exception.
        inline constexpr uint32_t K_MAX_BODY_INSTR = 144;

        // [growth-policy] Cap expanded instruction count for the constant-table unrolling exception.
        inline constexpr uint32_t K_MAX_TOTAL_INSTR = 576;

        // [growth-policy] Cap the original body size for ordinary full unrolling.
        inline constexpr uint32_t K_MAX_ORDINARY_BODY_INSTR = 96;

        // [growth-policy] Cap expanded instruction count for ordinary full unrolling.
        inline constexpr uint32_t K_MAX_ORDINARY_TOTAL_INSTR = 384;

        // [growth-policy] Use a smaller expansion budget when tests and jumps usually survive unrolling.
        inline constexpr uint32_t K_MAX_TOTAL_INSTR_WITH_BRANCHES = 96;

        // [growth-policy] Allow twice the ordinary expansion budget when nested loops all flatten.
        inline constexpr uint32_t K_MAX_NEST_TOTAL_INSTR = 2 * K_MAX_ORDINARY_TOTAL_INSTR;

        // [analysis-budget] Bound preheader searches for a loop counter initializer.
        inline constexpr uint32_t K_MAX_INIT_LOOKBACK = 8;

        // [analysis-budget] Bound preheader searches for an accumulator initializer before summation folding.
        inline constexpr uint32_t K_MAX_SUM_INIT_LOOKBACK = 16;

        // [growth-policy] Admit only short indexed bodies for partial unrolling to contain code growth.
        inline constexpr uint32_t K_MAX_PARTIAL_BODY_INSTR = 12;

        // [profitability-policy] Reserve two-copy partial unrolling for bodies large enough to amortize the remaining latch.
        inline constexpr uint32_t K_MIN_PAIRED_BODY_INSTR = 16;

        // [growth-policy] Amortize indexed-loop bound checks over this many scalar copies; all guards and offsets use the same
        // factor.
        inline constexpr uint64_t K_PARTIAL_UNROLL_FACTOR = 4;

        // [proof-domain-guard] Restrict recognized counted-loop steps; this is a conservative proof bound, not a machine operand
        // width.
        inline constexpr uint64_t K_MAX_COUNTED_STEP = 64;

        // [proof-domain-guard] Bound closed-form progression terms before modular accumulation,
        // and signed host arithmetic in the nested-loop size estimator. Ordinary unrolling
        // proves the trip distance in the counter's domain without this absolute bound.
        inline constexpr uint64_t K_MAX_COUNTED_BOUND = 1000000;

        // [proof-domain-guard] Bound tracked constant address offsets while estimating nested-loop unrolling.
        inline constexpr uint64_t K_MAX_DERIVED_OFFSET = 1000000;
    }

    namespace MemToReg
    {
        // [analysis-budget] Bound pending-store tracking for dead-store elimination; excess stores are retained conservatively.
        inline constexpr uint32_t K_MAX_PENDING = 64;
    }

    namespace PostRALoopHoist
    {
        // [analysis-budget] Bound repeated outer-loop hoisting after physical register allocation.
        inline constexpr uint32_t K_MAX_LEVELS = 3;

        // [analysis-budget] Bound the preheader search for an existing invariant memory read.
        inline constexpr uint32_t K_MAX_ENTRY_READ_LOOKBACK = 16;
    }

    namespace PostRALoopRotate
    {
        // [analysis-budget] Admit only short loop-test prefixes so rotation does not duplicate excessive code.
        inline constexpr uint32_t K_MAX_TEST_RUN = 8;

        // [analysis-budget] Bound recursive incoming-edge proofs before rotating a loop; exhaustion declines rotation.
        inline constexpr uint32_t K_MAX_EDGE_PROOF_VISITS = 512;
    }

    namespace PostRAPeephole
    {
        // [analysis-budget] Bound backward CFG proofs used by post-RA copy and liveness cleanup.
        inline constexpr uint32_t K_MAX_BACKTRACK = 256;

        // [analysis-budget] Bound forward CFG liveness proofs; exhaustion must prevent the rewrite.
        inline constexpr uint32_t K_MAX_WALK = 4096;

        // [analysis-budget] Bound incoming-path proofs before forwarding a stack slot into a register.
        inline constexpr uint32_t K_MAX_STACK_VALUE_VISITS = 256;
    }

    namespace PostRAPeepholeCommon
    {
        // [analysis-budget] Bound memory scans used to prove post-RA stores redundant or reusable.
        inline constexpr uint32_t K_MAX_STORE_SCAN_WINDOW = 32;

        // [analysis-budget] Bound each straight-line search for reloads of a value also stored in a local. Later reloads keep their spill home.
        inline constexpr uint32_t K_SPILL_RELOAD_WINDOW = 512;
    }

    namespace PostRAPeepholeCopyForward
    {
        // [analysis-budget] Bound the search proving a repeated register copy redundant.
        inline constexpr int K_MAX_SAME_COPY_WINDOW = 16;

        // [analysis-budget] Bound the search for a previous source copy usable by forwarding.
        inline constexpr uint32_t K_MAX_COPY_SOURCE_WINDOW = 16;

        // [analysis-budget] Bound the liveness proof before erasing an unobserved floating-point swap pair.
        inline constexpr uint32_t K_MAX_WINDOW = 64;

        // [analysis-budget] Bound reader renaming after removing a 64-bit integer copy.
        inline constexpr uint32_t K_INTEGER_COPY_WINDOW = 16;

        // [profitability-policy] A removed 64-bit MOV saves three bytes; at most three extra addressing bytes preserve code size.
        inline constexpr uint32_t K_INTEGER_COPY_REWRITES = 3;

        // [analysis-budget] Bound reader renaming after removing the second copy in a chain.
        inline constexpr uint32_t K_COPY_CHAIN_WINDOW = 16;

        // [profitability-policy] Cap reader rewrites so removing the second 64-bit copy cannot grow machine code.
        inline constexpr uint32_t K_COPY_CHAIN_REWRITES = 3;

        // [analysis-budget] Bound the search for a comparison of the old conversion result.
        inline constexpr uint32_t K_CONVERSION_COMPARE_WINDOW = 12;

        // [analysis-budget] Bound reader forwarding from a float-to-integer conversion result.
        inline constexpr uint32_t K_CONVERSION_RESULT_WINDOW = 16;

        // [analysis-budget] Bound forward reader checks before erasing an input-only integer register copy.
        inline constexpr uint32_t K_INTEGER_READER_WINDOW = 8;

        // [analysis-budget] Bound the backward search for a vector producer whose result can be redirected.
        inline constexpr uint32_t K_VECTOR_PRODUCER_WINDOW = 16;
    }

    namespace PostRAPeepholeFlags
    {
        // [analysis-budget] Bound the search for carry-dependent arithmetic patterns.
        inline constexpr uint32_t K_MAX_CARRY_PATTERN_WINDOW = 4;

        // [analysis-budget] Bound the search for a prior comparison with still-available flags.
        inline constexpr uint32_t K_REPEATED_COMPARE_WINDOW = 4;
    }

    namespace PostRAPeepholeFloatThreeOperand
    {
        // [analysis-budget] Bound the backward producer search for folding a floating-point copy.
        inline constexpr uint32_t K_MAX_COPY_FOLD_SCAN = 8;

        // [analysis-budget] Bound forward reader checks before redirecting a floating-point producer.
        inline constexpr uint32_t K_MAX_COPY_FOLD_LOOKAHEAD = 12;

        // [analysis-budget] Bound the multiply-to-accumulate distance when folding a memory operand.
        inline constexpr uint32_t K_MAX_PRODUCT_GAP = 6;

        // [analysis-budget] Bound the forward search for a consumer that can take a memory operand.
        inline constexpr uint32_t K_LOAD_CONSUMER_SCAN = 12;

        // [analysis-budget] Bound the backward search proving a destination already holds the same memory value.
        inline constexpr uint32_t K_MEMORY_DESTINATION_SCAN = 12;

        // [analysis-budget] Bound reader tracking when redirecting a copied square-root result.
        inline constexpr uint32_t K_MAX_WINDOW = 16;

        // [analysis-budget] Bound the forward accumulation search so a memory fold preserves opportunities for fused multiply-add.
        inline constexpr uint32_t K_MAX_FMA_ACCUMULATION_SCAN = 12;
    }

    namespace PostRAPeepholeLiveness
    {
        // [analysis-budget] Bound local physical-register liveness scans; an unfinished proof declines the rewrite.
        inline constexpr int K_MAX_LIVENESS_WINDOW = 32;
    }

    namespace PostRAPeepholeTrivial
    {
        // [analysis-budget] Bound the frame-access window inspected by trivial stack cleanup.
        inline constexpr uint32_t K_MAX_SPAN = 64;

        // [analysis-budget] Bound the return-tail search before removing redundant instructions.
        inline constexpr uint32_t K_MAX_RETURN_TAIL = 16;

        // [analysis-budget] Bound the exit-label search when merging two simple return tails.
        inline constexpr uint32_t K_MAX_RETURN_EXIT_SCAN = 12;
    }

    namespace PreRAPeepholeAddressForward
    {
        // [analysis-budget] Bound address forwarding through copies and stop before another rule has claimed an instruction.
        inline constexpr uint32_t K_MAX_ADDR_FORWARD_COPIES = 16;
    }

    namespace PrologEpilogSanitize
    {
        // [analysis-budget] Search only the entry prefix for a reservable body call frame; retain one lookahead instruction.
        inline constexpr uint32_t K_MAX_FRAME_SETUP_SCAN = 32;
    }

    namespace RegisterAllocation
    {
        // [storage-policy] Compact finalized acyclic liveness rows once their dense matrix
        // reaches 1 MiB. Smaller matrices keep direct dense storage and avoid row metadata.
        inline constexpr size_t K_COMPACT_LIVENESS_MIN_BYTES = 1024 * 1024;

        // [register-reserve] Keep integer scratch capacity when reserving registers for resident values.
        inline constexpr size_t K_RESIDENT_MIN_FREE_INT = 4;

        // [register-reserve] Keep floating-point scratch capacity when reserving registers for resident values.
        inline constexpr size_t K_RESIDENT_MIN_FREE_FLOAT = 2;

        // [profitability-policy] Keep register-benefit density comparisons in integer arithmetic.
        inline constexpr uint64_t K_DENSITY_SCALE = 1024;

        // [profitability-policy] Require half the best density for span-scoped claims; looser admission regressed sha256 and leven.
        inline constexpr uint64_t K_SPAN_SCOPED_DENSITY_DIVISOR = 2;

        // [register-reserve] Reserve four named integer operands plus three legalization scratch registers for local allocation.
        inline constexpr uint32_t K_MIN_FREE_INT_CLASS = 7;

        // [register-reserve] Reserve three floating-point operands plus one legalization scratch register for local allocation.
        inline constexpr uint32_t K_MIN_FREE_FLOAT_CLASS = 4;

        // [register-reserve] Keep two callee-saved integer escape hatches; one was insufficient on the first allocation sweep.
        inline constexpr uint32_t K_MIN_FREE_PERSISTENT_INT = 2;

        // [register-reserve] Keep a callee-saved floating-point escape hatch available for local allocation.
        inline constexpr uint32_t K_MIN_FREE_PERSISTENT_FLOAT = 1;

        // [profitability-policy] Require one depth-two boundary crossing under the decade-per-loop benefit model.
        inline constexpr uint64_t K_PERSISTENT_MIN_RAW_BENEFIT = 100;

        // [profitability-policy] Keep a mapping across a loop edge only when its next use is sufficiently near.
        inline constexpr uint32_t K_KEEP_MAX_NEXT_USE_DISTANCE = 48;

        // [analysis-budget] Bound copy-coalescing rounds that each rebuild allocation analyses.
        inline constexpr uint32_t K_MAX_JOIN_ROUNDS = 4;

        // [profitability-policy] Estimate repeated call-crossing spill cost inside a loop.
        inline constexpr uint8_t K_LOOP_CALL_WEIGHT = 10u;

        // [profitability-policy] Estimate tenfold execution frequency per loop level for global-register benefit; saturate at the
        // last entry.
        inline constexpr std::array<uint64_t, 10> K_LOOP_DEPTH_WEIGHTS = {
            1ull,
            10ull,
            100ull,
            1'000ull,
            10'000ull,
            100'000ull,
            1'000'000ull,
            10'000'000ull,
            100'000'000ull,
            1'000'000'000ull,
        };

        // [profitability-policy] Require enough weighted hot-call crossings to prefer a callee-saved float register.
        inline constexpr uint8_t K_PERSISTENT_FLOAT_CALL_WEIGHT = 10;
    }

    namespace RegisterAllocationInterval
    {
        // [convergence-guard-with-fallback] Allow repeated interval splitting while bounding livelock; exhaustion falls back to the local
        // allocator.
        inline constexpr uint32_t K_WALK_STEPS_PER_NODE = 16;

        // [convergence-guard-with-fallback] Give small interval graphs fixed splitting headroom before falling back to the local allocator.
        inline constexpr uint32_t K_WALK_STEP_SLACK = 256;

        // [profitability-policy] Saturate the loop-depth estimate used to compare spill-store placements.
        inline constexpr uint32_t K_MAX_STORE_COST_DEPTH = 8;

        // [profitability-policy] Estimate eightfold execution frequency per loop level for spill-store placement.
        inline constexpr uint32_t K_STORE_COST_DEPTH_SHIFT = 3;
    }

    namespace SinkToUse
    {
        // [analysis-budget] Bound rescheduling cascades as consumers and their producers move in successive rounds.
        inline constexpr uint32_t K_MAX_ROUNDS = 4;

        // [analysis-budget] Bound barrier scans so long materialization runs stay affordable to reschedule.
        inline constexpr uint32_t K_MAX_SINK_DISTANCE = 96;
    }

    namespace SlpVectorize
    {
        // [analysis-budget] Bound generated vector-plan size; oversized candidates remain scalar.
        inline constexpr uint32_t K_MAX_PLAN_INSTRS = 4096;

        // [analysis-budget] Bound recursive SLP tree construction; also used as the override ceiling, not a measured host-stack guarantee.
        inline constexpr uint32_t K_MAX_TREE_DEPTH = 512;
    }

    namespace StrengthReduction
    {
        // [analysis-budget] Bound the flag-preserving moves skipped before a remainder comparison with zero.
        inline constexpr uint32_t K_MAX_MOVES = 3;

        // [analysis-budget] Bound copy tracing in proofs that a remainder is used only in a zero test.
        inline constexpr uint32_t K_MAX_TEST_COPY_DEPTH = 8;

        // [analysis-budget] Bound copy tracing while recovering a value for strength reduction.
        inline constexpr uint32_t K_MAX_VALUE_COPY_DEPTH = 8;
    }

    namespace ValueNumbering
    {
        // [analysis-budget] Bound alias-chain resolution when comparing value-numbering keys.
        inline constexpr uint32_t K_MAX_ALIAS_DEPTH = 8;

        // [analysis-budget] Bound value-preserving copy tracing when canonicalizing an instruction use.
        inline constexpr uint32_t K_MAX_COPY_DEPTH = 8;
    }

    namespace VecLoopPromote
    {
        // [register-pressure] Limit simultaneously promoted vector state to contain register pressure.
        inline constexpr uint32_t K_MAX_PROMOTED_PER_LOOP = 6;
    }

    inline Runtime::BuildCfgBackendOptimizerUnroll resolveUnroll(const Runtime::BuildCfgBackendOptimizerUnroll& overrides)
    {
        Runtime::BuildCfgBackendOptimizerUnroll result = overrides;
        result.memoryBytes                             = static_cast<uint32_t>(configured(overrides.memoryBytes, Memory::K_DEFAULT_UNROLL_MEM_LIMIT));
        result.maxTrips                                = static_cast<uint32_t>(configured(overrides.maxTrips, LoopUnroll::K_MAX_TRIPS));
        result.maxWideTableTrips                       = static_cast<uint32_t>(configured(overrides.maxWideTableTrips, LoopUnroll::K_MAX_WIDE_TABLE_TRIPS));
        result.maxBodyInstructions                     = static_cast<uint32_t>(configured(overrides.maxBodyInstructions, LoopUnroll::K_MAX_BODY_INSTR));
        result.maxTotalInstructions                    = static_cast<uint32_t>(configured(overrides.maxTotalInstructions, LoopUnroll::K_MAX_TOTAL_INSTR));
        result.maxOrdinaryBodyInstructions             = static_cast<uint32_t>(configured(overrides.maxOrdinaryBodyInstructions, LoopUnroll::K_MAX_ORDINARY_BODY_INSTR));
        result.maxOrdinaryTotalInstructions            = static_cast<uint32_t>(configured(overrides.maxOrdinaryTotalInstructions, LoopUnroll::K_MAX_ORDINARY_TOTAL_INSTR));
        result.maxBranchedTotalInstructions            = static_cast<uint32_t>(configured(overrides.maxBranchedTotalInstructions, LoopUnroll::K_MAX_TOTAL_INSTR_WITH_BRANCHES));
        result.maxNestedTotalInstructions              = static_cast<uint32_t>(configured(overrides.maxNestedTotalInstructions, LoopUnroll::K_MAX_NEST_TOTAL_INSTR));
        result.maxPartialBodyInstructions              = static_cast<uint32_t>(configured(overrides.maxPartialBodyInstructions, LoopUnroll::K_MAX_PARTIAL_BODY_INSTR));
        result.partialFactor                           = static_cast<uint32_t>(configured(overrides.partialFactor, LoopUnroll::K_PARTIAL_UNROLL_FACTOR));
        result.initializerLookback                     = static_cast<uint32_t>(configured(overrides.initializerLookback, LoopUnroll::K_MAX_INIT_LOOKBACK));
        result.sumInitializerLookback                  = static_cast<uint32_t>(configured(overrides.sumInitializerLookback, LoopUnroll::K_MAX_SUM_INIT_LOOKBACK));
        result.partialFactor                           = std::min(result.partialFactor, LoopUnroll::K_MAX_PARTIAL_UNROLL_FACTOR);
        return result;
    }
}

SWC_END_NAMESPACE();
