#pragma once
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class Sema;
class LookupResult;

namespace SemaMatch
{
    void lookup(Sema& sema, LookupResult& result, IdentifierRef idRef);
};

SWC_END_NAMESPACE()
