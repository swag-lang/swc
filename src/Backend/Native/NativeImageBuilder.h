#pragma once
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;
struct LinkImage;
struct NativeObjDescription;

// Lowers prepared code/data and target unwind records to the common linker image.
class NativeImageBuilder
{
public:
    static Result build(LinkImage& image, NativeBackendBuilder& builder);
    static Result buildObject(LinkImage& image, NativeBackendBuilder& builder, const NativeObjDescription& description);
};

SWC_END_NAMESPACE();
