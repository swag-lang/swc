#include "pch.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
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
    std::string_view specOpSignatureHint(SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpDrop:
                return "func opDrop(me) -> void";
            case SpecOpKind::OpPostCopy:
                return "func opPostCopy(me) -> void";
            case SpecOpKind::OpPostMove:
                return "func opPostMove(me) -> void";
            case SpecOpKind::OpCount:
                return "func opCount(me) -> u64";
            case SpecOpKind::OpData:
                return "func opData(me) -> *<type>";
            case SpecOpKind::OpCast:
                return "func opCast(me) -> <type>";
            case SpecOpKind::OpEquals:
                return "func opEquals(me, value: <type>) -> bool";
            case SpecOpKind::OpCmp:
                return "func opCmp(me, value: <type>) -> s32";
            case SpecOpKind::OpBinary:
                return "func(op: string) opBinary(me, other: <type>) -> <struct>";
            case SpecOpKind::OpUnary:
                return "func(op: string) opUnary(me) -> <struct>";
            case SpecOpKind::OpAssign:
                return "func(op: string) opAssign(me, value: <type>) -> void";
            case SpecOpKind::OpAffect:
                return "func opAffect(me, value: <type>) -> void";
            case SpecOpKind::OpAffectLiteral:
                return "func(suffix: string) opAffectLiteral(me, value: <type>) -> void";
            case SpecOpKind::OpSlice:
                return "func opSlice(me, low: u64, up: u64) -> <string or slice>";
            case SpecOpKind::OpIndex:
                return "func opIndex(me, index: <type>) -> <type>";
            case SpecOpKind::OpIndexAssign:
                return "func(op: string) opIndexAssign(me, index: <type>, value: <type>) -> void";
            case SpecOpKind::OpIndexAffect:
                return "func(op: string) opIndexAffect(me, index: <type>, value: <type>) -> void";
            case SpecOpKind::OpVisit:
                return "func(ptr: bool, back: bool) opVisit(me, stmt: #code) -> void";
            default:
                return "valid special function signature";
        }
    }

    bool matchSpecOp(IdentifierRef idRef, const IdentifierManager& idMgr, SpecOpKind& outKind)
    {
        if (idRef.isInvalid())
            return false;

        using Pn = IdentifierManager::PredefinedName;
        struct Entry
        {
            Pn         pn;
            SpecOpKind kind;
        };

        static constexpr Entry K_MAP[] = {
            {Pn::OpVisit, SpecOpKind::OpVisit},
            {Pn::OpBinary, SpecOpKind::OpBinary},
            {Pn::OpUnary, SpecOpKind::OpUnary},
            {Pn::OpAssign, SpecOpKind::OpAssign},
            {Pn::OpIndexAssign, SpecOpKind::OpIndexAssign},
            {Pn::OpCast, SpecOpKind::OpCast},
            {Pn::OpEquals, SpecOpKind::OpEquals},
            {Pn::OpCmp, SpecOpKind::OpCmp},
            {Pn::OpPostCopy, SpecOpKind::OpPostCopy},
            {Pn::OpPostMove, SpecOpKind::OpPostMove},
            {Pn::OpDrop, SpecOpKind::OpDrop},
            {Pn::OpCount, SpecOpKind::OpCount},
            {Pn::OpData, SpecOpKind::OpData},
            {Pn::OpAffect, SpecOpKind::OpAffect},
            {Pn::OpAffectLiteral, SpecOpKind::OpAffectLiteral},
            {Pn::OpSlice, SpecOpKind::OpSlice},
            {Pn::OpIndex, SpecOpKind::OpIndex},
            {Pn::OpIndexAffect, SpecOpKind::OpIndexAffect},
        };

        for (const auto& e : K_MAP)
        {
            if (idRef == idMgr.predefined(e.pn))
            {
                outKind = e.kind;
                return true;
            }
        }

        const std::string_view name = idMgr.get(idRef).name;
        if (LangSpec::isOpVisitName(name))
        {
            outKind = SpecOpKind::OpVisit;
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

    Result reportSpecOpError(Sema& sema, const SymbolFunction& sym, SpecOpKind kind)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_spec_op_signature, sym);
        diag.addArgument(Diagnostic::ARG_BECAUSE, specOpSignatureHint(kind));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result validateSpecOpSignature(Sema& sema, const SymbolStruct& owner, SymbolFunction& sym, SpecOpKind kind)
    {
        auto&       ctx     = sema.ctx();
        const auto& typeMgr = sema.typeMgr();
        const auto& params  = sym.parameters();

        if (params.empty())
            return reportSpecOpError(sema, sym, kind);

        const TypeInfo& firstType = typeMgr.get(params[0]->typeRef());
        if (!firstType.isReference())
            return reportSpecOpError(sema, sym, kind);

        const TypeRef ownerTypeRef = unwrapAlias(ctx, owner.typeRef());
        const TypeRef firstPointee = unwrapAlias(ctx, firstType.payloadTypeRef());
        if (firstPointee != ownerTypeRef)
            return reportSpecOpError(sema, sym, kind);

        const TypeRef returnTypeRef = unwrapAlias(ctx, sym.returnTypeRef());
        if (returnTypeRef.isInvalid())
            return reportSpecOpError(sema, sym, kind);

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
            case SpecOpKind::OpDrop:
            case SpecOpKind::OpPostCopy:
            case SpecOpKind::OpPostMove:
                if (!requireExactParams(1) || !requireReturnVoid())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCount:
                if (!requireExactParams(1) || !requireReturnType(typeMgr.typeU64()))
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpData:
                if (!requireExactParams(1) || !requireReturnPointer())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCast:
                if (!requireExactParams(1) || !requireReturnNotVoid())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpEquals:
                if (!requireExactParams(2) || !requireReturnType(typeMgr.typeBool()))
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCmp:
                if (!requireExactParams(2) || !requireReturnType(typeMgr.typeS32()))
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpBinary:
                if (!requireExactParams(2) || !requireReturnStruct())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpUnary:
                if (!requireExactParams(1) || !requireReturnStruct())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpAssign:
                if (!requireExactParams(2) || !requireReturnVoid())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpAffect:
                if (!requireExactParams(2) || !requireReturnVoid() || !requireSecondNotStruct())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpAffectLiteral:
                if (!requireExactParams(2) || !requireReturnVoid() || !requireSecondNotStruct())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpSlice:
                if (!requireExactParams(3) || !requireReturnStringOrSlice() || !requireU64Param(1) || !requireU64Param(2))
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpIndex:
                if (!requireMinParams(2) || !requireReturnNotVoid())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpIndexAssign:
            case SpecOpKind::OpIndexAffect:
                if (!requireMinParams(3) || !requireReturnVoid())
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpVisit:
                if (!requireExactParams(2) || !requireReturnVoid())
                    return reportSpecOpError(sema, sym, kind);
                break;
        }

        return Result::Continue;
    }

    bool allowsSpecOpOverload(SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpCast:
            case SpecOpKind::OpEquals:
            case SpecOpKind::OpCmp:
            case SpecOpKind::OpBinary:
            case SpecOpKind::OpAssign:
            case SpecOpKind::OpAffect:
            case SpecOpKind::OpAffectLiteral:
            case SpecOpKind::OpIndex:
            case SpecOpKind::OpIndexAssign:
            case SpecOpKind::OpIndexAffect:
                return true;
            default:
                return false;
        }
    }

    SymbolStruct* ownerStructFor(SymbolFunction& sym)
    {
        SymbolStruct* ownerStruct = nullptr;
        if (auto* symMap = sym.ownerSymMap())
        {
            if (const auto* symImpl = symMap->safeCast<SymbolImpl>())
                ownerStruct = symImpl->symStruct();
            else
                ownerStruct = symMap->safeCast<SymbolStruct>();
        }

        return ownerStruct;
    }
}

Result SemaSpecOp::validateSymbol(Sema& sema, SymbolFunction& sym)
{
    const IdentifierRef idRef = sym.idRef();
    if (idRef.isInvalid())
        return Result::Continue;

    auto&                  idMgr = sema.idMgr();
    const std::string_view name  = idMgr.get(idRef).name;
    if (!LangSpec::isSpecOpName(name))
        return Result::Continue;

    SpecOpKind kind{};
    if (!matchSpecOp(idRef, idMgr, kind))
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_spec_op_unknown, sym);
        diag.addNote(DiagnosticId::sema_note_spec_op_reserved);
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (kind == SpecOpKind::OpVisit && name.size() > std::string_view("opVisit").size())
    {
        const char variantStart = name[std::string_view("opVisit").size()];
        if (std::isupper(static_cast<unsigned char>(variantStart)) == 0)
            return reportSpecOpError(sema, sym, kind);
    }

    SymbolStruct* ownerStruct = ownerStructFor(sym);
    if (!ownerStruct)
        return SemaError::raise(sema, DiagnosticId::sema_err_spec_op_outside_impl, sym);

    RESULT_VERIFY(validateSpecOpSignature(sema, *ownerStruct, sym, kind));
    sym.addExtraFlag(SymbolFunctionFlagsE::SpecOpValidated);
    return Result::Continue;
}

Result SemaSpecOp::registerSymbol(Sema& sema, SymbolFunction& sym)
{
    const IdentifierRef idRef = sym.idRef();
    if (idRef.isInvalid())
        return Result::Continue;

    auto&                  idMgr = sema.idMgr();
    const std::string_view name  = idMgr.get(idRef).name;
    if (!LangSpec::isSpecOpName(name))
        return Result::Continue;

    if (!sym.hasExtraFlag(SymbolFunctionFlagsE::SpecOpValidated))
        return Result::Continue;

    SpecOpKind kind{};
    if (!matchSpecOp(idRef, idMgr, kind))
        return Result::Continue;

    SymbolStruct* ownerStruct = ownerStructFor(sym);
    if (!ownerStruct)
        return Result::Continue;

    if (!allowsSpecOpOverload(kind))
    {
        const auto here = ownerStruct->getSpecOp(sym.idRef());
        if (!here.empty())
            return SemaError::raiseAlreadyDefined(sema, &sym, here.front());
    }

    return ownerStruct->registerSpecOp(sym, kind);
}

SWC_END_NAMESPACE();
