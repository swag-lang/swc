#pragma once
#include "Sema/Core/Sema.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class SymbolNamespace;

class SemaJob : public Job
{
    Sema             sema_;
    SymbolNamespace* moduleNamespace_ = nullptr;

public:
    static constexpr auto K = JobKind::Sema;

    SemaJob(const TaskContext& ctx, SemaInfo& semaInfo, bool declPass);
    SemaJob(const TaskContext& ctx, const Sema& parentSema, AstNodeRef root);
    JobResult exec();

    Sema&       sema() { return sema_; }
    const Sema& sema() const { return sema_; }
};

SWC_END_NAMESPACE();
