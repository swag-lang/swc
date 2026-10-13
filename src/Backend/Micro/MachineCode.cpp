#include "pch.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

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

Result MachineCode::emit(TaskContext& ctx, MicroBuilder& builder, MicroReg debugStackBaseVirtualReg, uint16_t sanitizerSafetyMask, const SymbolFunction* sanitizerFunction)
{
    const Runtime::BuildCfgBackend& backendBuildCfg = ctx.compiler().buildCfg().backend;
    // Windows uses the PE exception directory for ordinary stack walking too. Omitting it from a
    // release DLL makes RtlCaptureStackBackTrace stop at that module boundary, so panic reports lose
    // the application caller even when the artifact carries Swag symbols.
    const bool computeUnwindInfo = ctx.compiler().cmdLine().targetOs == Runtime::TargetOs::Windows || backendBuildCfg.enableExceptions || backendBuildCfg.debugInfo;

    MicroPassContext passContext;
    passContext.callConvKind             = CallConvKind::Swag;
    passContext.preservePersistentRegs   = true;
    passContext.forceFramePointer        = computeUnwindInfo;
    passContext.debugStackBaseVirtualReg = debugStackBaseVirtualReg;
    passContext.keepLocalStackBase       = backendBuildCfg.debugInfo;
    passContext.sanitizerSafetyMask      = sanitizerSafetyMask;
    passContext.sanitizerFunction        = sanitizerFunction;

#ifdef _M_X64
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

    encoder.setBackendBuildCfg(builder.backendBuildCfg());
    encoder.clearDebugSourceRanges();

    SWC_RESULT(builder.runPasses(&encoder, passContext));

    debugStackBasePhysReg = passContext.debugStackBasePhysReg;
    codeAlignment         = passContext.codeAlignment;

    // Diagnostics can abort lowering before any encodable instruction is produced.
    // Propagate the existing failure instead of crashing in the test runner.
    const auto codeSize = encoder.size();
    if (codeSize == 0)
        return Result::Error;

    bytes.resize(codeSize);
    encoder.copyTo(bytes);
    if (computeUnwindInfo)
        encoder.buildUnwindInfo(unwindInfo);
    else
        unwindInfo.clear();

    // Both producers end here: the encoder is local, and every builder handed to this function is
    // discarded once its code is lowered.
    codeRelocations   = std::move(builder.codeRelocations());
    debugSourceRanges = encoder.releaseDebugSourceRanges();

    return Result::Continue;
}

SWC_END_NAMESPACE();
