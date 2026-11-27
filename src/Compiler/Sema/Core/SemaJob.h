#pragma once
#include "Compiler/Sema/Core/Sema.h"
#include "Support/Core/RefTypes.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class SymbolNamespace;

class SemaJob : public Job
{
    // Separate ownership lets completed jobs release their semantic state
    // while the compiler retains the job until module teardown.
    std::unique_ptr<Sema> sema_;
    SymbolNamespace*      moduleNamespace_          = nullptr;
    SymbolFunction*       lazyFunction_             = nullptr;
    bool                  enqueueFullPassAfterDecl_ = false;

#if SWC_DEV_MODE
    // Survives the release of the Sema, for scheduler statistics.
    const SourceFile* file_ = nullptr;
#endif

public:
    static constexpr auto K = JobKind::Sema;

    SemaJob(const TaskContext& ctx, NodePayload& nodePayloadContext, bool declPass);
    SemaJob(const TaskContext& ctx, NodePayload& nodePayloadContext, bool declPass, bool enqueueFullPassAfterDecl);
    SemaJob(const TaskContext& ctx, Sema& parentSema, AstNodeRef root);
    SemaJob(const TaskContext& ctx, Sema& parentSema, NodePayload& nodePayloadContext, AstNodeRef root);

    // Analyzes the deferred body of 'function' for a consumer that reached it without a caller
    // analysis to complete it, such as native code generation.
    SemaJob(const TaskContext& ctx, NodePayload& nodePayloadContext, SymbolFunction& function);

    JobResult exec() override;

#if SWC_DEV_MODE
    Utf8 statsLabel() const override;
#endif

    Sema&       sema() { return *sema_; }
    const Sema& sema() const { return *sema_; }

    // Null once the job has finished and released its Sema.
    Sema*       trySema() { return sema_.get(); }
    const Sema* trySema() const { return sema_.get(); }
};

SWC_END_NAMESPACE();
