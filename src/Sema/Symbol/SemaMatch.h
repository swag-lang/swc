#pragma once
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class Symbol;
class Sema;
class LookUpContext;
class SymbolMap;

namespace SemaMatch
{
    Result match(Sema& sema, LookUpContext& lookUpCxt, IdentifierRef idRef);
    Result ghosting(Sema& sema, const Symbol& sym);
}

SWC_END_NAMESPACE()
