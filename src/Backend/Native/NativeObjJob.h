#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class NativeObjJob final : public Job
{
public:
    static constexpr auto K = JobKind::NativeObj;

    NativeObjJob(const TaskContext& ctx, NativeBackendBuilder& builder, uint32_t objIndex);

private:
    JobResult exec();

    NativeBackendBuilder* builder_  = nullptr;
    uint32_t              objIndex_ = 0;
};

SWC_END_NAMESPACE();
