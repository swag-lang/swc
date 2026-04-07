#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Memory/MemoryProfile.h"
#if SWC_HAS_STATS
#include "Support/Core/Timer.h"
#endif
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    JobResult waitCodeGenPreSolved(TaskContext& ctx, const SymbolFunction& waiterSymbol, const Symbol& waitedSymbol, AstNodeRef nodeRef)
    {
        TaskState& wait   = ctx.state();
        wait.kind         = TaskStateKind::SemaWaitSymCodeGenPreSolved;
        wait.nodeRef      = nodeRef;
        wait.codeRef      = waiterSymbol.codeRef();
        wait.symbol       = &waitedSymbol;
        wait.waiterSymbol = &waiterSymbol;
        return JobResult::Sleep;
    }

    JobResult abortCodeGen(TaskContext& ctx, SymbolFunction& symbolFunc, Result result)
    {
        if (result == Result::Error)
            symbolFunc.setIgnored(ctx);
        return Job::toJobResult(ctx, result);
    }
}

CodeGenJob::CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root) :
    Job(ctx, JobKind::CodeGen),
    symbolFunc_(&symbolFunc),
    root_(root)
{
    // Resolve the NodePayload now (cheap pointer lookup), defer Sema/CodeGen creation to exec().
    const SourceView& symbolSrcView = sema.compiler().srcView(symbolFunc.srcViewRef());
    const FileRef     symbolFileRef = symbolSrcView.fileRef();
    if (symbolFileRef.isValid())
        nodePayloadCtx_ = &sema.compiler().file(symbolFileRef).nodePayloadContext();

    if (!nodePayloadCtx_)
    {
        const SourceFile* semaFile = sema.file();
        SWC_ASSERT(semaFile != nullptr);
        const FileRef semaFileRef = sema.ast().srcView().fileRef();
        nodePayloadCtx_ = &sema.compiler().file(semaFileRef).nodePayloadContext();
    }

    func = [this] {
        return exec();
    };
}

void CodeGenJob::initSemaAndCodeGen()
{
    SWC_ASSERT(nodePayloadCtx_ != nullptr);
    ownedSema_ = std::make_unique<Sema>(ctx(), *nodePayloadCtx_, false);
    codeGen_   = std::make_unique<CodeGen>(*ownedSema_);
}

JobResult CodeGenJob::exec()
{
    SWC_MEM_SCOPE("Backend/CodeGen");
    SWC_ASSERT(symbolFunc_);
    ctx().state().reset();
    if (symbolFunc_->isIgnored())
        return abortCodeGen(ctx(), *symbolFunc_, Result::Error);
    if (symbolFunc_->isCodeGenCompleted())
        return JobResult::Done;
    if (symbolFunc_->attributes().hasRtFlag(RtAttributeFlagsE::Macro) || symbolFunc_->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
    {
        symbolFunc_->setCodeGenPreSolved(ctx());
        symbolFunc_->setCodeGenCompleted(ctx());
        return JobResult::Done;
    }

    if (!ownedSema_)
        initSemaAndCodeGen();

    const Result selfWaitResult = sema().waitSemaCompleted(symbolFunc_, symbolFunc_->codeRef());
    if (selfWaitResult != Result::Continue)
        return abortCodeGen(ctx(), *symbolFunc_, selfWaitResult);

    SmallVector<SymbolFunction*> deps;
    symbolFunc_->appendCallDependencies(deps);

    // Collect dependencies only after sema completion. The call graph can still
    // grow while semantic analysis is running, and codegen can discover extra
    // lowering-time helpers later, so we refresh it again below before
    // declaring codegen completed.
    ///////////////////////////////////////////
    for (const SymbolFunction* dep : deps)
    {
        const Result depWaitResult = sema().waitSemaCompleted(dep, dep->codeRef());
        if (depWaitResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, depWaitResult);
        if (dep->isIgnored())
            return abortCodeGen(ctx(), *symbolFunc_, Result::Error);
    }

    // Schedule codegen jobs for dependencies that are not scheduled yet.
    ///////////////////////////////////////////
    for (SymbolFunction* dep : deps)
    {
        if (!dep->tryMarkCodeGenJobScheduled())
            continue;
        const AstNodeRef depRoot = dep->declNodeRef();
        SWC_ASSERT(depRoot.isValid());
        auto* depJob = heapNew<CodeGenJob>(ctx(), sema(), *dep, depRoot);
        sema().compiler().global().jobMgr().enqueue(*depJob, JobPriority::Normal, sema().compiler().jobClientId());
    }

    // Generate micro instructions only once and mark codegen as pre-solved.
    ///////////////////////////////////////////
    if (!symbolFunc_->isCodeGenPreSolved())
    {
        SWC_ASSERT(root_.isValid());
#if SWC_HAS_STATS
        Timer timeCodeGen(&Stats::get().timeCodeGen);
#endif
        const Result codeGenResult = codeGen_->exec(*symbolFunc_, root_);
        if (codeGenResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, codeGenResult);

        symbolFunc_->setCodeGenPreSolved(ctx());

        // Lowered microcode persisted on the symbol for later materialization.
        ///////////////////////////////////////////
        const Result emitResult = symbolFunc_->emit(ctx());
        if (emitResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, emitResult);
    }

    SmallVector<SymbolFunction*> finalDeps;
    symbolFunc_->appendCallDependencies(finalDeps);

    // Finalize only when every dependency observed after codegen has reached a
    // lowered state. This preserves parallel scheduling while ensuring
    // functions discovered during sema/codegen are also joined.
    ///////////////////////////////////////////
    for (SymbolFunction* dep : finalDeps)
    {
        const Result depWaitResult = sema().waitSemaCompleted(dep, dep->codeRef());
        if (depWaitResult != Result::Continue)
            return abortCodeGen(ctx(), *symbolFunc_, depWaitResult);
        if (dep->isIgnored())
            return abortCodeGen(ctx(), *symbolFunc_, Result::Error);

        if (dep->tryMarkCodeGenJobScheduled())
        {
            const AstNodeRef depRoot = dep->declNodeRef();
            SWC_ASSERT(depRoot.isValid());
            auto* depJob = heapNew<CodeGenJob>(ctx(), sema(), *dep, depRoot);
            sema().compiler().global().jobMgr().enqueue(*depJob, JobPriority::Normal, sema().compiler().jobClientId());
        }

        if (!dep->isCodeGenPreSolved() && !dep->isCodeGenCompleted())
            return waitCodeGenPreSolved(ctx(), *symbolFunc_, *dep, root_);
    }

    symbolFunc_->setCodeGenCompleted(ctx());
    return JobResult::Done;
}

SWC_END_NAMESPACE();
