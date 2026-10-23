#pragma once
#include "Backend/ABI/CallConvKind.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/RuntimeBackendConfig.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class MicroBuilder;
class MicroSsaState;
struct MicroSsaValueScratch;
struct MicroOptimizerFunctionStats;
class TaskContext;
class Encoder;
class SymbolFunction;

// A frame object as the code generator laid it out: a stack local or an addressable
// parameter home, at an offset from the local-stack base register.
struct MicroFrameObject
{
    uint64_t offset    = 0;
    uint64_t size      = 0;
    uint32_t alignment = 1;
};

struct MicroPassContext
{
    MicroPassContext() = default;

    // Selected call convention drives register classes, stack alignment, and saved regs.
    Encoder*              encoder                 = nullptr;
    TaskContext*          taskContext             = nullptr;
    MicroBuilder*         builder                 = nullptr;
    MicroStorage*         instructions            = nullptr;
    MicroOperandStorage*  operands                = nullptr;
    std::span<const Utf8> passPrintOptions        = {};
    CallConvKind          callConvKind            = CallConvKind::Swag;
    bool                  preservePersistentRegs  = false;
    bool                  forceFramePointer       = false;
    bool                  validateMicro           = false;
    bool                  usesIntReturnRegOnRet   = true;
    bool                  usesFloatReturnRegOnRet = true;

    // The function's effective runtime-safety mask (build-config default combined with
    // any `#[Swag.Safety(...)]` overrides). The static sanitizer runs the checks whose
    // safety guard is set here, so it honours per-scope safety, not just the global
    // build configuration. 0 (the default, used for compiler-generated code) disables it.
    uint16_t sanitizerSafetyMask = 0;

    // Alignment the start of the emitted code needs in the image, raised by the emit pass
    // when it placed code against a window wider than the default function alignment.
    uint32_t codeAlignment = 16;

    // The function being lowered, for sanitizer checks that need its signature (return
    // type nullability, ...). Null for compiler-generated code.
    const SymbolFunction* sanitizerFunction = nullptr;

    // Debug info: the virtual register that holds the local-stack base (the value all local
    // variables are addressed against). Set by the caller before the pass pipeline runs.
    // Register allocation records the physical register it resolves to in debugStackBasePhysReg,
    // and PrologEpilog keeps that in sync across any physical-register remap. Without this the
    // debug records would name a virtual register, which CodeView cannot encode, so every local
    // would be silently dropped and invisible in the debugger.
    MicroReg debugStackBaseVirtualReg = MicroReg::invalid();
    MicroReg debugStackBasePhysReg    = MicroReg::invalid();

    // The local-stack base only has to live in a register of its own when debug records name
    // it. Otherwise register allocation reads the locals through the stack pointer when that
    // pointer never moves in the body (see foldLocalStackBaseIntoStackPointer), and records it
    // here: the frame then holds locals the stack pointer addresses directly.
    bool keepLocalStackBase   = false;
    bool localStackBaseFolded = false;

    // Raw displacement envelope of allocator spill accesses. Stack adjustments can make an
    // outgoing argument use a displacement in this envelope too; ownership needs the
    // entry-relative frame below. Empty (lo >= hi) when nothing spilled.
    uint64_t spillAreaLo = std::numeric_limits<uint64_t>::max();
    uint64_t spillAreaHi = 0;

    // Bytes reserved exclusively for allocator homes, relative to incoming SP.
    // Allocation sweeps extend this prefix; the prologue relocates it below saved registers.
    int64_t spillFrameEntryLo = 0;
    int64_t spillFrameEntryHi = 0;

    // The frame objects, in offset order (see MicroPassHelpers::frameObjects). Built from the
    // lowered function's symbols on first use; the frame compaction pass publishes the layout it
    // leaves behind here, so later passes never read the stale lowering offsets.
    mutable SmallVector<MicroFrameObject> frameObjects;
    mutable bool                          frameObjectsReady = false;

    // Persistent SIMD registers whose full incoming value the emitted prologue
    // already saves and every epilogue restores. Post-RA caches may borrow one
    // only when physical liveness proves it idle throughout their region.
    uint32_t savedFloatRegMask = 0;

    // First instruction of the blocks the final layout moved behind the function's last return
    // (see MicroColdBlockLayoutPass). Each of them jumps back into the body, and emission must
    // not read those jumps as the back edges of loops. Invalid when nothing was moved.
    MicroInstrRef coldTailRef = MicroInstrRef::invalid();

    // Shared SSA analysis for pre-RA optimization passes.
    // Built lazily by MicroSsaState::ensureFor and invalidated when a pass mutates the IR.
    MicroSsaState* ssaState = nullptr;

    // Temporary SSA value propagation storage owned by the worker running this pipeline.
    MicroSsaValueScratch* ssaValueScratch = nullptr;

    // Null unless optimizer profiling was requested. Never shared with another worker.
    MicroOptimizerFunctionStats* optimizerStats = nullptr;

    const Runtime::BuildCfgBackendOptimizer& optimizer() const;

    // Optional fixed-point iteration cap for optimization loops (0 = use level default).
    uint32_t optimizationIterationLimit = 0;
    size_t   printInstrCountBefore      = 0;
    bool     passChanged                = false;

    // Keep scalar XOR load/modify/store triples visible until SLP has seen
    // their adjacent stores. The cleanup sweep folds any triples left scalar.
    bool deferXorMemoryFoldForSlp = false;
    bool deferredXorMemoryFold    = false;

    // True during the first sweep of a bounded optimization loop. Post-RA
    // forwarding transforms (copy/const forwarding) are only sound on the
    // pristine IR straight out of register allocation, where the spill-reload
    // and ABI-marshalling shapes they target live; they must not re-run on
    // already-cleaned-up IR. Erase/DCE cleanups have no such restriction.
    bool isFirstOptimizationSweep = true;

    // True during the first sweep of the legalize/allocate loop, i.e. while
    // register allocation is still assigning the whole function. Legalization
    // of the allocator's own output introduces fresh virtual scratch registers,
    // which sends the loop round again; that later sweep allocates a handful of
    // values into a function whose registers are already committed, and it has
    // no record of the whole-range reservations the first sweep made. Only the
    // first sweep may hand a value a register for its entire live range.
    bool isFirstAllocationSweep = true;

    // Physical registers the first allocation sweep handed to a value for its
    // entire live range. A later sweep allocates into a function whose
    // registers are already committed, and it rebuilds its state from scratch,
    // so nothing else remembers those reservations: without this list it can
    // hand a scratch value a register that still holds a live one, and no
    // repair path can notice — the value it displaces has no spill home to be
    // restored from. Reset with the rest of the pipeline state.
    SmallVector<MicroReg> globalReservedRegs;

    // The first sweep assigned the function with the interval allocator.
    // Its output holds every value under a register's own name, so a
    // later sweep allocates through the concrete-liveness guards alone and
    // globalReservedRegs lists what that sweep may borrow around a scratch -
    // every pool register - rather than what it must keep away from.
    bool intervalAllocated = false;
};

SWC_END_NAMESPACE();
