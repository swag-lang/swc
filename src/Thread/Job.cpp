#include "pch.h"

#include "Thread/JobManager.h"

void Job::wakeDependents() const
{
    if (!owner_ || !rec_)
        return; // not scheduled
    std::unique_lock<std::mutex> lk(owner_->mtx_);
    owner_->notifyDependents(rec_);
}
