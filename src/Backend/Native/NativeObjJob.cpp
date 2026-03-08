#include "pch.h"
#include "Backend/Native/NativeObjJob.h"

SWC_BEGIN_NAMESPACE();

namespace NativeBackendDetail
{
    NativeObjJob::NativeObjJob(const TaskContext& ctx, NativeBackendBuilder& builder, const uint32_t objIndex) :
        Job(ctx, JobKind::NativeObj),
        builder_(&builder),
        objIndex_(objIndex)
    {
        func = [this] {
            return exec();
        };
    }

    JobResult NativeObjJob::exec()
    {
        ctx().state().reset();
        if (!builder_)
            return JobResult::Done;
        if (!builder_->writeObject(objIndex_))
            builder_->objWriteFailed_.store(true, std::memory_order_release);
        return JobResult::Done;
    }
}

SWC_END_NAMESPACE();
