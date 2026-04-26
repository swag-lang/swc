#pragma once
#include "Compiler/Sema/Core/Sema.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class SymbolNamespace;

class SemaJob : public Job
{
    Sema             sema_;
    SymbolNamespace* moduleNamespace_          = nullptr;
    bool             enqueueFullPassAfterDecl_ = false;

public:
    static constexpr auto K = JobKind::Sema;

    SemaJob(const TaskContext& ctx, NodePayload& nodePayloadContext, bool declPass);
    SemaJob(const TaskContext& ctx, NodePayload& nodePayloadContext, bool declPass, bool enqueueFullPassAfterDecl);
    SemaJob(const TaskContext& ctx, Sema& parentSema, AstNodeRef root);
    SemaJob(const TaskContext& ctx, Sema& parentSema, NodePayload& nodePayloadContext, AstNodeRef root);
    JobResult exec() override;

    Sema&       sema() { return sema_; }
    const Sema& sema() const { return sema_; }
};

SWC_END_NAMESPACE();
