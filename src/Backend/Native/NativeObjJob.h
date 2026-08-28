#pragma once
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;

class NativeObjJob final : public Job
{
public:
    static constexpr auto K = JobKind::NativeObj;

    NativeObjJob(const TaskContext& ctx, NativeBackendBuilder& builder, uint32_t objIndex);

    JobResult exec() override;

private:
    NativeBackendBuilder* builder_  = nullptr;
    uint32_t              objIndex_ = 0;
};

SWC_END_NAMESPACE();
