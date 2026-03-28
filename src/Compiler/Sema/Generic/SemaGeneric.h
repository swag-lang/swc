#pragma once
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolStruct;

namespace SemaGeneric
{
    Result instantiateFunctionExplicit(Sema& sema, SymbolFunction& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolFunction*& outInstance);
    Result instantiateFunctionFromCall(Sema& sema, SymbolFunction& genericRoot, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SymbolFunction*& outInstance);
    Result instantiateStructExplicit(Sema& sema, SymbolStruct& genericRoot, std::span<const AstNodeRef> genericArgNodes, SymbolStruct*& outInstance);
}

SWC_END_NAMESPACE();
