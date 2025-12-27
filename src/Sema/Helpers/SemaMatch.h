#pragma once
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class Sema;
class MatchResult;
class SymbolMap;
enum class LookUpResult;

namespace SemaMatch
{
    void lookupAppend(Sema& sema, const SymbolMap& symMap, MatchResult& result, IdentifierRef idRef);
    void lookup(Sema& sema, MatchResult& result, IdentifierRef idRef);
    LookUpResult ghosting(Sema& sema, Symbol& sym);
}

SWC_END_NAMESPACE()
