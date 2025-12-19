#pragma once
#include "Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

struct AstEnumDecl;

struct SemaFrame
{
    SymbolAccess                defaultAccess = SymbolAccess::Private;
    std::optional<SymbolAccess> currentAccess;
    AstEnumDecl*                currentEnumDecl = nullptr;
};

SWC_END_NAMESPACE()
