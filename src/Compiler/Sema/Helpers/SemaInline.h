#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

class Sema;

namespace SemaInline
{
    struct ArgMapping
    {
        IdentifierRef paramIdRef = IdentifierRef::invalid();
        AstNodeRef    argRef     = AstNodeRef::invalid();
    };

    bool   canInlineCall(Sema& sema, const SymbolFunction& fn);
    Result tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg);
}

struct SemaInlinePayload
{
    const SymbolFunction*                            sourceFunction = nullptr;
    SymbolVariable*                                  resultVar      = nullptr;
    SmallVector<SemaInline::ArgMapping, 6>           argMappings;
    std::array<IdentifierRef, 10>                    aliasIdentifiers = {};
    std::array<IdentifierRef, SemaScope::UNIQ_COUNT> uniqIdentifiers  = {};
    AstNodeRef                                       callRef          = AstNodeRef::invalid();
    AstNodeRef                                       inlineRootRef    = AstNodeRef::invalid();
    TypeRef                                          returnTypeRef    = TypeRef::invalid();
};

SWC_END_NAMESPACE();
