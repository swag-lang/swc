#include "pch.h"
#include "Backend/Native/NativeObjJob.h"
#include "Support/Memory/MemoryProfile.h"

SWC_BEGIN_NAMESPACE();

NativeObjJob::NativeObjJob(const TaskContext& ctx, NativeBackendBuilder& builder, const uint32_t objIndex) :
    Job(ctx, JobKind::NativeObj),
    builder_(&builder),
    objIndex_(objIndex)
{
}

JobResult NativeObjJob::exec()
{
    SWC_MEM_SCOPE("Backend/Native/ObjWrite");
    ctx().state().reset();
    SWC_ASSERT(builder_ != nullptr);
    if (builder_->writeObject(objIndex_) != Result::Continue)
        builder_->objWriteFailed.store(true, std::memory_order_release);
    return JobResult::Done;
}

SWC_END_NAMESPACE();
