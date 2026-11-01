#pragma once
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;
struct LinkImage;

// Lowers prepared code/data and target unwind records to the common linker image.
class NativeImageBuilder
{
public:
    static Result build(LinkImage& image, NativeBackendBuilder& builder);
};

SWC_END_NAMESPACE();
