#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::string_view specialFunctionSignatureHint(SpecialFuncKind kind)
    {
        switch (kind)
        {
            case SpecialFuncKind::OpDrop:
                return "func opDrop(me) -> void";
            case SpecialFuncKind::OpPostCopy:
                return "func opPostCopy(me) -> void";
            case SpecialFuncKind::OpPostMove:
                return "func opPostMove(me) -> void";
            case SpecialFuncKind::OpCount:
                return "func opCount(me) -> u64";
            case SpecialFuncKind::OpData:
                return "func opData(me) -> *<type>";
            case SpecialFuncKind::OpCast:
                return "func opCast(me) -> <type>";
            case SpecialFuncKind::OpEquals:
                return "func opEquals(me, value: <type>) -> bool";
            case SpecialFuncKind::OpCmp:
                return "func opCmp(me, value: <type>) -> s32";
            case SpecialFuncKind::OpBinary:
                return "func(op: string) opBinary(me, other: <type>) -> <struct>";
            case SpecialFuncKind::OpUnary:
                return "func(op: string) opUnary(me) -> <struct>";
            case SpecialFuncKind::OpAssign:
                return "func(op: string) opAssign(me, value: <type>) -> void";
            case SpecialFuncKind::OpAffect:
                return "func opAffect(me, value: <type>) -> void";
            case SpecialFuncKind::OpAffectLiteral:
                return "func(suffix: string) opAffectLiteral(me, value: <type>) -> void";
            case SpecialFuncKind::OpSlice:
                return "func opSlice(me, low: u64, up: u64) -> <string or slice>";
            case SpecialFuncKind::OpIndex:
                return "func opIndex(me, index: <type>) -> <type>";
            case SpecialFuncKind::OpIndexAssign:
                return "func(op: string) opIndexAssign(me, index: <type>, value: <type>) -> void";
            case SpecialFuncKind::OpIndexAffect:
                return "func(op: string) opIndexAffect(me, index: <type>, value: <type>) -> void";
            case SpecialFuncKind::OpVisit:
                return "func(ptr: bool, back: bool) opVisit(me, stmt: #code) -> void";
            default:
                return "valid special function signature";
        }
    }

    bool matchSpecialFunction(IdentifierRef idRef, const IdentifierManager& idMgr, SpecialFuncKind& outKind)
    {
        if (idRef.isInvalid())
            return false;

        using Pn = IdentifierManager::PredefinedName;
        struct Entry
        {
            Pn              pn;
            SpecialFuncKind kind;
        };

        static constexpr Entry K_MAP[] = {
            {Pn::OpVisit, SpecialFuncKind::OpVisit},
            {Pn::OpBinary, SpecialFuncKind::OpBinary},
            {Pn::OpUnary, SpecialFuncKind::OpUnary},
            {Pn::OpAssign, SpecialFuncKind::OpAssign},
            {Pn::OpIndexAssign, SpecialFuncKind::OpIndexAssign},
            {Pn::OpCast, SpecialFuncKind::OpCast},
            {Pn::OpEquals, SpecialFuncKind::OpEquals},
            {Pn::OpCmp, SpecialFuncKind::OpCmp},
            {Pn::OpPostCopy, SpecialFuncKind::OpPostCopy},
            {Pn::OpPostMove, SpecialFuncKind::OpPostMove},
            {Pn::OpDrop, SpecialFuncKind::OpDrop},
            {Pn::OpCount, SpecialFuncKind::OpCount},
            {Pn::OpData, SpecialFuncKind::OpData},
            {Pn::OpAffect, SpecialFuncKind::OpAffect},
            {Pn::OpAffectLiteral, SpecialFuncKind::OpAffectLiteral},
            {Pn::OpSlice, SpecialFuncKind::OpSlice},
            {Pn::OpIndex, SpecialFuncKind::OpIndex},
            {Pn::OpIndexAffect, SpecialFuncKind::OpIndexAffect},
        };

        for (const auto& e : K_MAP)
        {
            if (idRef == idMgr.predefined(e.pn))
            {
                outKind = e.kind;
                return true;
            }
        }

        // Slow/fallback path: name-based visit operator.
        const std::string_view name = idMgr.get(idRef).name;
        if (LangSpec::isOpVisitName(name))
        {
            outKind = SpecialFuncKind::OpVisit;
            return true;
        }

        return false;
    }

    TypeRef unwrapAlias(TaskContext& ctx, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return typeRef;
        return ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias);
    }

    TypeRef unwrapPointerOrRef(TaskContext& ctx, TypeRef typeRef)
    {
        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isReference() || type.isAnyPointer())
            return unwrapAlias(ctx, type.payloadTypeRef());
        return unwrapAlias(ctx, typeRef);
    }

    Result reportSpecialFunctionError(Sema& sema, const SymbolFunction& sym, SpecialFuncKind kind)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_special_function_signature, sym);
        diag.addArgument(Diagnostic::ARG_BECAUSE, specialFunctionSignatureHint(kind));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result validateSpecialFunctionSignature(Sema& sema, const SymbolStruct& owner, SymbolFunction& sym, SpecialFuncKind kind)
    {
        auto&       ctx     = sema.ctx();
        const auto& typeMgr = sema.typeMgr();
        const auto& params  = sym.parameters();

        if (params.empty())
            return reportSpecialFunctionError(sema, sym, kind);

        const TypeInfo& firstType = typeMgr.get(params[0]->typeRef());
        if (!firstType.isReference())
            return reportSpecialFunctionError(sema, sym, kind);

        const TypeRef ownerTypeRef = unwrapAlias(ctx, owner.typeRef());
        const TypeRef firstPointee = unwrapAlias(ctx, firstType.payloadTypeRef());
        if (firstPointee != ownerTypeRef)
            return reportSpecialFunctionError(sema, sym, kind);

        const TypeRef returnTypeRef = unwrapAlias(ctx, sym.returnTypeRef());
        if (returnTypeRef.isInvalid())
            return reportSpecialFunctionError(sema, sym, kind);

        const TypeInfo& returnType = typeMgr.get(returnTypeRef);

        auto requireExactParams = [&](size_t count) -> bool {
            return params.size() == count;
        };

        auto requireMinParams = [&](size_t count) -> bool {
            return params.size() >= count;
        };

        auto requireReturnVoid = [&] -> bool {
            return returnType.isVoid();
        };

        auto requireReturnNotVoid = [&] -> bool {
            return !returnType.isVoid();
        };

        auto requireReturnType = [&](TypeRef typeRef) -> bool {
            return unwrapAlias(ctx, typeRef) == returnTypeRef;
        };

        auto requireReturnStruct = [&] -> bool {
            return returnType.isStruct() && &returnType.payloadSymStruct() == &owner;
        };

        auto requireReturnPointer = [&] -> bool {
            return returnType.isAnyPointer();
        };

        auto requireReturnStringOrSlice = [&] -> bool {
            return returnType.isString() || returnType.isSlice();
        };

        auto requireU64Param = [&](size_t index) -> bool {
            return unwrapAlias(ctx, params[index]->typeRef()) == unwrapAlias(ctx, typeMgr.typeU64());
        };

        auto requireSecondNotStruct = [&] -> bool {
            if (params.size() < 2)
                return false;
            const TypeRef   underlying = unwrapPointerOrRef(ctx, params[1]->typeRef());
            const TypeInfo& type       = typeMgr.get(underlying);
            if (!type.isStruct())
                return true;
            return &type.payloadSymStruct() != &owner;
        };

        switch (kind)
        {
            case SpecialFuncKind::OpDrop:
            case SpecialFuncKind::OpPostCopy:
            case SpecialFuncKind::OpPostMove:
                if (!requireExactParams(1) || !requireReturnVoid())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpCount:
                if (!requireExactParams(1) || !requireReturnType(typeMgr.typeU64()))
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpData:
                if (!requireExactParams(1) || !requireReturnPointer())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpCast:
                if (!requireExactParams(1) || !requireReturnNotVoid())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpEquals:
                if (!requireExactParams(2) || !requireReturnType(typeMgr.typeBool()))
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpCmp:
                if (!requireExactParams(2) || !requireReturnType(typeMgr.typeS32()))
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpBinary:
                if (!requireExactParams(2) || !requireReturnStruct())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpUnary:
                if (!requireExactParams(1) || !requireReturnStruct())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpAssign:
                if (!requireExactParams(2) || !requireReturnVoid())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpAffect:
                if (!requireExactParams(2) || !requireReturnVoid() || !requireSecondNotStruct())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpAffectLiteral:
                if (!requireExactParams(2) || !requireReturnVoid() || !requireSecondNotStruct())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpSlice:
                if (!requireExactParams(3) || !requireReturnStringOrSlice() || !requireU64Param(1) || !requireU64Param(2))
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpIndex:
                if (!requireMinParams(2) || !requireReturnNotVoid())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpIndexAssign:
            case SpecialFuncKind::OpIndexAffect:
                if (!requireMinParams(3) || !requireReturnVoid())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;

            case SpecialFuncKind::OpVisit:
                if (!requireExactParams(2) || !requireReturnVoid())
                    return reportSpecialFunctionError(sema, sym, kind);
                break;
        }

        return Result::Continue;
    }

}

Result registerStructSpecialFunction(Sema& sema, SymbolFunction& sym)
{
    const IdentifierRef idRef = sym.idRef();
    if (idRef.isInvalid())
        return Result::Continue;

    auto&                  idMgr = sema.idMgr();
    const std::string_view name  = idMgr.get(idRef).name;
    if (!LangSpec::isSpecialFunctionName(name))
        return Result::Continue;

    SpecialFuncKind kind{};
    if (!matchSpecialFunction(idRef, idMgr, kind))
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_special_function_unknown, sym);
        diag.addNote(DiagnosticId::sema_note_special_function_reserved);
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (kind == SpecialFuncKind::OpVisit && name.size() > std::string_view("opVisit").size())
    {
        const char variantStart = name[std::string_view("opVisit").size()];
        if (std::isupper(static_cast<unsigned char>(variantStart)) == 0)
            return reportSpecialFunctionError(sema, sym, kind);
    }

    SymbolStruct* ownerStruct = nullptr;
    if (auto* symMap = sym.ownerSymMap())
    {
        if (const auto* symImpl = symMap->safeCast<SymbolImpl>())
            ownerStruct = symImpl->symStruct();
        else
            ownerStruct = symMap->safeCast<SymbolStruct>();
    }

    if (!ownerStruct)
        return SemaError::raise(sema, DiagnosticId::sema_err_special_function_outside_impl, sym);

    RESULT_VERIFY(validateSpecialFunctionSignature(sema, *ownerStruct, sym, kind));
    return ownerStruct->registerSpecialFunction(sema, sym, kind);
}

SWC_END_NAMESPACE();
