#include "pch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/RuntimeName.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using MicroPhysLiveness = MicroPassHelpers::MicroPhysLiveness;

    uint64_t physicalRegBits(const MicroRegSpan regs)
    {
        uint64_t bits = 0;
        for (const MicroReg reg : regs)
            bits |= 1ull << MicroPhysLiveness::bitOf(reg);
        return bits;
    }

    // Reads the final code, after every pass and with the encoder's own writes (a gather's mask,
    // the RDX of a division), so a caller trusting the result keeps nothing this code touches.
    // The return registers stay clobbered even when the body leaves them alone: every call
    // hands its result back in them.
    uint64_t leafCallClobbers(const MicroBuilder& builder, const Encoder& encoder, CallConvKind callConvKind)
    {
        const CallConv& conv     = CallConv::get(callConvKind);
        uint64_t        clobbers = physicalRegBits(std::array{conv.intReturn, conv.floatReturn});

        MicroInstrUseDef useDef;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                return MicroInstr::K_CALL_CLOBBERS_ALL;

            inst.collectUseDef(useDef, builder.operands(), &encoder);
            for (const MicroReg reg : useDef.defs)
            {
                const uint32_t bit = MicroPhysLiveness::bitOf(reg);
                if (bit < MicroPhysLiveness::K_INVALID_BIT)
                    clobbers |= 1ull << bit;
            }
        }

        // The function saves and restores any nonvolatile register it writes.
        return clobbers & (physicalRegBits(conv.intTransientRegs) | physicalRegBits(conv.floatTransientRegs));
    }
}

const MachineCode::DebugSourceRange* MachineCode::findDebugSourceRangeAtOffset(const uint32_t codeOffset) const
{
    for (const auto& range : debugSourceRanges)
    {
        if (codeOffset < range.codeStartOffset || codeOffset >= range.codeEndOffset)
            continue;
        return &range;
    }

    return nullptr;
}

bool MachineCode::tryResolveDebugSourceRange(const TaskContext& ctx, ResolvedDebugSourceRange& outResolvedRange, const DebugSourceRange& range)
{
    outResolvedRange = {};
    if (!tryResolveDebugSourceInfo(ctx, outResolvedRange.source, range.debugSourceInfo))
        return false;

    outResolvedRange.debugRange = &range;
    return true;
}

bool MachineCode::tryResolveDebugSourceRangeAtOffset(const TaskContext& ctx, ResolvedDebugSourceRange& outResolvedRange, const uint32_t codeOffset) const
{
    outResolvedRange = {};

    const auto* range = findDebugSourceRangeAtOffset(codeOffset);
    if (!range)
        return false;

    return tryResolveDebugSourceRange(ctx, outResolvedRange, *range);
}

const ByteArray& MachineCode::jitUnwindInfo(const TaskContext& ctx) const
{
    // A Windows leaf legitimately has no unwind bytes; emptiness cannot select
    // between the native target format and the compiler host format.
    return ctx.cmdLine().targetOs == hostTargetOs() ? unwindInfo : hostUnwindInfo;
}

Result MachineCode::emit(TaskContext& ctx, MicroBuilder& builder, MicroReg debugStackBaseVirtualReg, uint16_t sanitizerSafetyMask, const SymbolFunction* function)
{
    const Runtime::BuildCfgBackend& backendBuildCfg = ctx.compiler().buildCfg().backend;
    // Both supported hosts require unwind metadata for ordinary stack walking. Linux
    // also needs it to run native cleanup when a registered JIT frame faults, even
    // when language exceptions and debug information are disabled.
    const bool computeUnwindInfo = (ctx.compiler().cmdLine().targetOs == Runtime::TargetOs::Windows || ctx.compiler().cmdLine().targetOs == Runtime::TargetOs::Linux) || backendBuildCfg.enableExceptions || backendBuildCfg.debugInfo;

    MicroPassContext passContext;
    passContext.callConvKind             = function ? function->callConvKind() : CallConvKind::Swag;
    passContext.preservePersistentRegs   = true;
    passContext.forceFramePointer        = computeUnwindInfo;
    passContext.debugStackBaseVirtualReg = debugStackBaseVirtualReg;
    passContext.keepLocalStackBase       = backendBuildCfg.debugInfo;
    passContext.sanitizerSafetyMask      = sanitizerSafetyMask;
    passContext.sanitizerFunction        = function;

#if defined(_M_X64) || defined(__x86_64__)
    // One encoder per worker: its pages, unwind tracker and debug ranges are reset for the
    // next function instead of being allocated and freed with each one. The lease keeps a
    // lowering that nests inside another on this thread, should one ever appear, on an encoder
    // of its own.
    struct WorkerEncoder
    {
        std::optional<X64Encoder> encoder;
        bool                      leased = false;
    };
    thread_local WorkerEncoder worker;
    struct EncoderLease
    {
        WorkerEncoder*            worker = nullptr;
        std::optional<X64Encoder> nested;
        X64Encoder*               encoder = nullptr;

        EncoderLease(WorkerEncoder& sharedWorker, TaskContext& ctx)
        {
            if (sharedWorker.leased)
            {
                encoder = &nested.emplace(ctx);
                return;
            }

            worker = &sharedWorker;
            if (sharedWorker.encoder)
                sharedWorker.encoder->reset(ctx);
            else
                sharedWorker.encoder.emplace(ctx);
            sharedWorker.leased = true;
            encoder             = &*sharedWorker.encoder;
        }

        ~EncoderLease()
        {
            if (worker)
                worker->leased = false;
        }
    };
    EncoderLease lease(worker, ctx);
    X64Encoder&  encoder = *lease.encoder;
#endif

    encoder.enableHostUnwind();
    encoder.setBackendBuildCfg(builder.backendBuildCfg());
    encoder.clearDebugSourceRanges();

    SWC_RESULT(builder.runPasses(&encoder, passContext));

    debugStackBasePhysReg = passContext.debugStackBasePhysReg;
    codeAlignment         = passContext.codeAlignment;
    callClobbers          = leafCallClobbers(builder, encoder, passContext.callConvKind);

    // Diagnostics can abort lowering before any encodable instruction is produced.
    // Propagate the existing failure instead of crashing in the test runner.
    const auto codeSize = encoder.size();
    if (codeSize == 0)
        return Result::Error;

    bytes.resize(codeSize);
    encoder.copyTo(bytes);
    if (computeUnwindInfo)
    {
        encoder.buildUnwindInfo(unwindInfo);
        encoder.buildHostUnwindInfo(hostUnwindInfo);
    }
    else
    {
        unwindInfo.clear();
        hostUnwindInfo.clear();
    }

    // Both producers end here: the encoder is local, and every builder handed to this function is
    // discarded once its code is lowered.
    codeRelocations   = std::move(builder.codeRelocations());
    debugSourceRanges = encoder.releaseDebugSourceRanges();

    return Result::Continue;
}

SWC_END_NAMESPACE();
