#pragma once
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class Sema;
class LookupResult;
class SymbolMap;
enum class LookUpReturn;

namespace SemaMatch
{
    void lookupAppend(Sema& sema, const SymbolMap& symMap, LookupResult& result, IdentifierRef idRef);
    void lookup(Sema& sema, LookupResult& result, IdentifierRef idRef);
    LookUpReturn ghosting(Sema& sema, Symbol& sym, IdentifierRef idRef);
}

SWC_END_NAMESPACE()
