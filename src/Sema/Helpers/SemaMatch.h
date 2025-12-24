#pragma once
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class Sema;
class LookupResult;
class SymbolMap;

namespace SemaMatch
{
    void lookup(Sema& sema, const SymbolMap& symMap, LookupResult& result, IdentifierRef idRef);
    void lookup(Sema& sema, LookupResult& result, IdentifierRef idRef);
};

SWC_END_NAMESPACE()
