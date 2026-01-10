#pragma once
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class Sema;
class MatchContext;
class SymbolMap;

namespace Match
{
    Result match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef);
    Result ghosting(Sema& sema, const Symbol& sym);
}

SWC_END_NAMESPACE();
