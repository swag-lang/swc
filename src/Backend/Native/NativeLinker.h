#pragma once

#include "Backend/Native/NativeBackendTypes.h"

SWC_BEGIN_NAMESPACE();

class NativeLinker
{
public:
    virtual ~NativeLinker() = default;

    static std::unique_ptr<NativeLinker> create(NativeBackendBuilder& builder);

    virtual Result link() = 0;
};

SWC_END_NAMESPACE();
