#include "pch.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

void Job::wakeDependents() const
{
    if (!owner_ || !rec_)
        return;
    std::unique_lock lk(owner_->mtx_);
    owner_->notifyDependents(rec_);
}

void Job::clearIntents()
{
    dep_.reset();
    child_.reset();
    childPriority_ = JobPriority::Normal;
}

SWC_END_NAMESPACE()
