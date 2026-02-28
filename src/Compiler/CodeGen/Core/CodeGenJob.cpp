#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Global.h"
#include "Wmf/SourceFile.h"
#if SWC_HAS_STATS
#include "Main/Stats.h"
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
}

CodeGenJob::CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root) :
    Job(ctx, JobKind::CodeGen),
    symbolFunc_(&symbolFunc),
    root_(root)
{
    Sema* codeGenSema = &sema;
    if (symbolFunc.srcViewRef() != sema.ast().srcView().ref())
    {
        const SourceView& symbolSrcView = sema.compiler().srcView(symbolFunc.srcViewRef());
        const FileRef     symbolFileRef = symbolSrcView.fileRef();
        if (symbolFileRef.isValid())
        {
            SourceFile& symbolFile = sema.compiler().file(symbolFileRef);
            ownedSema_             = std::make_unique<Sema>(Job::ctx(), symbolFile.nodePayloadContext(), false);
            codeGenSema            = ownedSema_.get();
        }
    }

    codeGen_ = std::make_unique<CodeGen>(*SWC_NOT_NULL(codeGenSema));
    func     = [this] {
        return exec();
    };
}

JobResult CodeGenJob::exec()
{
    SWC_ASSERT(symbolFunc_);
    ctx().state().reset();
    if (symbolFunc_->isCodeGenCompleted())
        return JobResult::Done;

    SmallVector<SymbolFunction*> deps;
    symbolFunc_->appendCallDependencies(deps);

    // Wait for sema completion on this function and all direct codegen dependencies.
    ///////////////////////////////////////////
    const Result selfWaitResult = sema().waitSemaCompleted(symbolFunc_, symbolFunc_->codeRef());
    if (selfWaitResult != Result::Continue)
        return toJobResult(selfWaitResult);
    for (const SymbolFunction* dep : deps)
    {
        const Result depWaitResult = sema().waitSemaCompleted(dep, dep->codeRef());
        if (depWaitResult != Result::Continue)
            return toJobResult(depWaitResult);
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
            return toJobResult(codeGenResult);
        symbolFunc_->setCodeGenPreSolved(ctx());

        // Lowered microcode persisted on the symbol for later materialization.
        ///////////////////////////////////////////
        const Result emitResult = symbolFunc_->emit(ctx());
        if (emitResult != Result::Continue)
            return toJobResult(emitResult);
    }

    // Finalize only when dependency codegen is already pre-solved or completed.
    ///////////////////////////////////////////
    for (const SymbolFunction* dep : deps)
    {
        if (!dep->isCodeGenPreSolved() && !dep->isCodeGenCompleted())
            return waitCodeGenPreSolved(ctx(), *symbolFunc_, *dep, root_);
    }

    symbolFunc_->setCodeGenCompleted(ctx());
    return JobResult::Done;
}

SWC_END_NAMESPACE();
