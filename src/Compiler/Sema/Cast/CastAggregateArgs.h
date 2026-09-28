#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class TypeInfo;
struct CastRequest;

struct CastAggregateArgs
{
    Sema*           sema;
    CastRequest*    castRequest;
    TypeRef         srcTypeRef;
    TypeRef         dstTypeRef;
    const TypeInfo* srcType;
    const TypeInfo* dstType;
};

SWC_END_NAMESPACE();
