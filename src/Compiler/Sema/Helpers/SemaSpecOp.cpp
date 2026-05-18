#include "pch.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Ast/Sema.Index.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Memory/Heap.h"
#include "Support/Os/Os.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::string_view specOpSignatureHint(SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpDrop:
                return "mtd opDrop() -> void";
            case SpecOpKind::OpPostCopy:
                return "mtd opPostCopy() -> void";
            case SpecOpKind::OpPostMove:
                return "mtd opPostMove() -> void";
            case SpecOpKind::OpCount:
                return "mtd opCount() -> u64";
            case SpecOpKind::OpData:
                return "mtd opData() -> *<type>";
            case SpecOpKind::OpCast:
                return "mtd opCast() -> <type>";
            case SpecOpKind::OpEquals:
                return "mtd opEquals(value: <type>) -> bool";
            case SpecOpKind::OpCompare:
                return "mtd opCompare(value: <type>) -> s32";
            case SpecOpKind::OpBinary:
                return "mtd(op: string) const opBinary(other: <type>) -> <struct>";
            case SpecOpKind::OpBinaryRight:
                return "mtd(op: string) const opBinaryRight(other: <type>) -> <struct>";
            case SpecOpKind::OpUnary:
                return "mtd(op: string) const opUnary() -> <struct>";
            case SpecOpKind::OpAssign:
                return "mtd(op: string) opAssign(value: <type>) -> void";
            case SpecOpKind::OpSet:
                return "mtd opSet(value: <type>) -> void";
            case SpecOpKind::OpSetLiteral:
                return "mtd(suffix: string) opSetLiteral(value: <type>) -> void";
            case SpecOpKind::OpSlice:
                return "mtd opSlice(low: u64, up: u64) -> <string or slice>";
            case SpecOpKind::OpIndex:
                return "mtd opIndex(index: <type>[, index: <same type>...]) -> <type>";
            case SpecOpKind::OpIndexAssign:
                return "mtd(op: string) opIndexAssign(index: <type>[, index: <same type>...], value: <type>) -> void";
            case SpecOpKind::OpIndexSet:
                return "mtd opIndexSet(index: <type>[, index: <same type>...], value: <type>) -> void";
            case SpecOpKind::OpVisit:
                return "mtd(ptr: bool, back: bool) opVisit(stmt: #code) -> void";
            case SpecOpKind::None:
            case SpecOpKind::Invalid:
            default:
                return "valid operator overload signature";
        }
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

    bool isSpecOpReceiver(TaskContext& ctx, const SymbolStruct& owner, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isReference())
            typeRef = type.payloadTypeRef();

        const TypeRef receiverTypeRef = unwrapAlias(ctx, typeRef);
        if (receiverTypeRef == unwrapAlias(ctx, owner.typeRef()))
            return true;

        if (!receiverTypeRef.isValid())
            return false;

        const TypeInfo& receiverType = ctx.typeMgr().get(receiverTypeRef);
        if (!receiverType.isStruct())
            return false;

        const SymbolStruct& receiverStruct = receiverType.payloadSymStruct();
        if (receiverStruct.isGenericInstance() && receiverStruct.genericRootSym() == &owner)
            return true;
        if (owner.isGenericInstance() && owner.genericRootSym() == &receiverStruct)
            return true;
        const SymbolStruct* receiverRoot = receiverStruct.isGenericInstance() ? receiverStruct.genericRootSym() : &receiverStruct;
        const SymbolStruct* ownerRoot    = owner.isGenericInstance() ? owner.genericRootSym() : &owner;
        if (receiverRoot && ownerRoot && receiverRoot == ownerRoot)
            return true;
        return false;
    }

    bool isConstSpecOpReceiver(TaskContext& ctx, const SymbolStruct& owner, TypeRef typeRef)
    {
        if (!isSpecOpReceiver(ctx, owner, typeRef))
            return false;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        return type.isConst();
    }

    bool isOpBinarySecondParamImmutable(TaskContext& ctx, const SymbolFunction& sym, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isReference() || type.isPointerLike())
            return type.isConst();

        if (sym.isGenericRoot())
            return false;

        return true;
    }

    bool indexParametersHaveSameType(TaskContext& ctx, const std::vector<SymbolVariable*>& params, size_t firstIndex, size_t endIndex)
    {
        SWC_ASSERT(firstIndex < endIndex);
        SWC_ASSERT(endIndex <= params.size());
        SWC_ASSERT(params[firstIndex] != nullptr);

        const TypeRef firstTypeRef = unwrapAlias(ctx, params[firstIndex]->typeRef());
        for (size_t i = firstIndex + 1; i < endIndex; ++i)
        {
            SWC_ASSERT(params[i] != nullptr);
            if (unwrapAlias(ctx, params[i]->typeRef()) != firstTypeRef)
                return false;
        }

        return true;
    }

    std::span<const TokenId> expectedSpecOpGenericValueTypes(SpecOpKind kind)
    {
        static constexpr TokenId K_STRING[] = {TokenId::TypeString};
        static constexpr TokenId K_BOOL2[]  = {TokenId::TypeBool, TokenId::TypeBool};

        switch (kind)
        {
            case SpecOpKind::OpBinary:
            case SpecOpKind::OpBinaryRight:
            case SpecOpKind::OpUnary:
            case SpecOpKind::OpAssign:
            case SpecOpKind::OpSetLiteral:
            case SpecOpKind::OpIndexAssign:
                return K_STRING;

            case SpecOpKind::OpVisit:
                return K_BOOL2;

            default:
                return {};
        }
    }

    const AstFunctionDecl* specOpDeclForGenericSignature(const SymbolFunction& sym)
    {
        const SymbolFunction* root = &sym;
        if (sym.isGenericInstance() && sym.genericRootSym())
            root = sym.genericRootSym();

        return root->decl() ? root->decl()->safeCast<AstFunctionDecl>() : nullptr;
    }

    bool hasSpecOpGenericValueType(const Sema& sema, const Ast& ast, AstNodeRef typeRef, TokenId expectedType)
    {
        if (typeRef.isInvalid())
            return false;

        const AstNode& typeNode = ast.node(typeRef);
        if (typeNode.isNot(AstNodeId::BuiltinType))
            return false;

        return sema.token(typeNode.codeRef()).id == expectedType;
    }

    bool hasSpecOpGenericSignature(Sema& sema, const SymbolFunction& sym, SpecOpKind kind)
    {
        const auto  expected = expectedSpecOpGenericValueTypes(kind);
        const auto* decl     = specOpDeclForGenericSignature(sym);

        if (sym.isGenericInstance() && !sym.isGenericRoot())
            return true;

        if (!decl)
            return expected.empty();

        if (!decl->spanGenericParamsRef.isValid())
            return expected.empty();

        if (expected.empty())
            return false;

        const Ast* declAst = nullptr;
        if (sema.ast().tryFindNodeRef(decl).isValid())
        {
            declAst = &sema.ast();
        }
        else
        {
            const SourceView& declSrcView = sema.compiler().srcView(decl->srcViewRef());
            if (const SourceFile* sourceFile = declSrcView.file())
                declAst = &sourceFile->ast();
        }

        if (!declAst)
            return false;

        SmallVector<AstNodeRef> params;
        declAst->appendNodes(params, decl->spanGenericParamsRef);
        if (params.size() != expected.size())
            return false;

        for (size_t i = 0; i < params.size(); ++i)
        {
            const auto* nodeValue = declAst->node(params[i]).safeCast<AstGenericParamValue>();
            if (!nodeValue)
                return false;
            if (nodeValue->nodeAssignRef.isValid())
                return false;
            if (!hasSpecOpGenericValueType(sema, *declAst, nodeValue->nodeTypeRef, expected[i]))
                return false;
        }

        return true;
    }

    Result reportSpecOpError(Sema& sema, const SymbolFunction& sym, SpecOpKind kind)
    {
        const auto& codeRef = sym.codeRef();
        Diagnostic  diag    = SemaError::build(sema, DiagnosticId::sema_err_spec_op_signature, codeRef);
        SemaError::setReportArguments(sema, diag, &sym);
        diag.addNote(DiagnosticId::sema_note_expected_signature);
        diag.last().addArgument(Diagnostic::ARG_VALUE, specOpSignatureHint(kind));
        diag.report(sema.ctx());
        return Result::Continue;
    }

    Result validateSpecOpSignature(Sema& sema, const SymbolStruct& owner, SymbolFunction& sym, SpecOpKind kind)
    {
        TaskContext&       ctx     = sema.ctx();
        const TypeManager& typeMgr = sema.typeMgr();
        const auto&        params  = sym.parameters();

        if (!hasSpecOpGenericSignature(sema, sym, kind))
            return reportSpecOpError(sema, sym, kind);

        if (params.empty())
            return reportSpecOpError(sema, sym, kind);

        if (!isSpecOpReceiver(ctx, owner, params[0]->typeRef()))
            return reportSpecOpError(sema, sym, kind);

        const TypeRef returnTypeRef = unwrapAlias(ctx, sym.returnTypeRef());
        if (returnTypeRef.isInvalid())
            return reportSpecOpError(sema, sym, kind);

        const TypeInfo& returnType       = typeMgr.get(returnTypeRef);
        const bool      receiverIsConst  = isConstSpecOpReceiver(ctx, owner, params[0]->typeRef());
        const bool      returnIsVoid     = returnType.isVoid();
        const bool      returnIsStruct   = returnType.isStruct() && &returnType.payloadSymStruct() == &owner;
        const bool      returnIsPointer  = returnType.isAnyPointer();
        const bool      returnIsNotVoid  = !returnIsVoid;
        const bool      returnIsStrSlice = returnType.isString() || returnType.isSlice();
        const TypeRef   u64TypeRef       = unwrapAlias(ctx, typeMgr.typeU64());
        const TypeRef   boolTypeRef      = unwrapAlias(ctx, typeMgr.typeBool());
        const TypeRef   s32TypeRef       = unwrapAlias(ctx, typeMgr.typeS32());
        switch (kind)
        {
            case SpecOpKind::None:
                return Result::Continue;
            case SpecOpKind::Invalid:
                return reportSpecOpError(sema, sym, kind);
            case SpecOpKind::OpDrop:
            case SpecOpKind::OpPostCopy:
            case SpecOpKind::OpPostMove:
                if (params.size() != 1 || !returnIsVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCount:
                if (params.size() != 1 || returnTypeRef != u64TypeRef)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpData:
                if (params.size() != 1 || !returnIsPointer)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCast:
                if (params.size() != 1 || !returnIsNotVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpEquals:
                if (params.size() != 2 || returnTypeRef != boolTypeRef)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpCompare:
                if (params.size() != 2 || returnTypeRef != s32TypeRef)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpBinary:
            case SpecOpKind::OpBinaryRight:
                if (params.size() != 2 || !receiverIsConst || !isOpBinarySecondParamImmutable(ctx, sym, params[1]->typeRef()) || !returnIsStruct)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpUnary:
                if (params.size() != 1 || !receiverIsConst || !returnIsStruct)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpAssign:
                if (params.size() != 2 || !returnIsVoid)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpSet:
            case SpecOpKind::OpSetLiteral:
            {
                if (params.size() != 2 || !returnIsVoid)
                    return reportSpecOpError(sema, sym, kind);

                const TypeRef   underlying = unwrapPointerOrRef(ctx, params[1]->typeRef());
                const TypeInfo& type       = typeMgr.get(underlying);
                if (type.isStruct() && &type.payloadSymStruct() == &owner)
                    return reportSpecOpError(sema, sym, kind);

                break;
            }

            case SpecOpKind::OpSlice:
                if (params.size() != 3 || !returnIsStrSlice || unwrapAlias(ctx, params[1]->typeRef()) != u64TypeRef || unwrapAlias(ctx, params[2]->typeRef()) != u64TypeRef)
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpIndex:
                if (params.size() < 2 || !returnIsNotVoid || !indexParametersHaveSameType(ctx, params, 1, params.size()))
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpIndexAssign:
            case SpecOpKind::OpIndexSet:
                if (params.size() < 3 || !returnIsVoid || !indexParametersHaveSameType(ctx, params, 1, params.size() - 1))
                    return reportSpecOpError(sema, sym, kind);
                break;

            case SpecOpKind::OpVisit:
                if (params.size() != 2 || !returnIsVoid)
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
            case SpecOpKind::OpCompare:
            case SpecOpKind::OpBinary:
            case SpecOpKind::OpBinaryRight:
            case SpecOpKind::OpAssign:
            case SpecOpKind::OpSet:
            case SpecOpKind::OpSetLiteral:
            case SpecOpKind::OpIndex:
            case SpecOpKind::OpIndexAssign:
            case SpecOpKind::OpIndexSet:
                return true;
            default:
                return false;
        }
    }

}

std::string_view SemaSpecOp::specOpFunctionName(const SpecOpKind kind)
{
    switch (kind)
    {
        case SpecOpKind::OpDrop:
            return "opDrop";
        case SpecOpKind::OpPostCopy:
            return "opPostCopy";
        case SpecOpKind::OpPostMove:
            return "opPostMove";
        case SpecOpKind::OpCount:
            return "opCount";
        case SpecOpKind::OpData:
            return "opData";
        case SpecOpKind::OpCast:
            return "opCast";
        case SpecOpKind::OpEquals:
            return "opEquals";
        case SpecOpKind::OpCompare:
            return "opCompare";
        case SpecOpKind::OpBinary:
            return "opBinary";
        case SpecOpKind::OpBinaryRight:
            return "opBinaryRight";
        case SpecOpKind::OpUnary:
            return "opUnary";
        case SpecOpKind::OpAssign:
            return "opAssign";
        case SpecOpKind::OpSet:
            return "opSet";
        case SpecOpKind::OpSetLiteral:
            return "opSetLiteral";
        case SpecOpKind::OpSlice:
            return "opSlice";
        case SpecOpKind::OpIndex:
            return "opIndex";
        case SpecOpKind::OpIndexAssign:
            return "opIndexAssign";
        case SpecOpKind::OpIndexSet:
            return "opIndexSet";
        case SpecOpKind::OpVisit:
            return "opVisit";
        case SpecOpKind::None:
        case SpecOpKind::Invalid:
        default:
            return "operator overload";
    }
}

void SemaSpecOp::addMissingDeclarationHelp(Sema& sema, Diagnostic& diag, const SymbolStruct& ownerStruct, SpecOpKind kind)
{
    const SymbolStruct* rootStruct = &ownerStruct;
    if (ownerStruct.isGenericInstance() && ownerStruct.genericRootSym())
        rootStruct = ownerStruct.genericRootSym();

    DiagnosticElement* help = SemaError::addCurrentModuleHelp(sema, diag, *rootStruct, DiagnosticId::sema_help_missing_spec_op);
    if (!help)
        return;

    help->addArgument(Diagnostic::ARG_DECL_SYM, rootStruct->name(sema.ctx()));
    help->addArgument(Diagnostic::ARG_SPEC_OP, SemaSpecOp::specOpFunctionName(kind));
    help->addArgument(Diagnostic::ARG_SPEC_OP_SIGNATURE, specOpSignatureHint(kind));
}

Result SemaSpecOp::validateSymbol(Sema& sema, SymbolFunction& sym)
{
    const IdentifierRef      idRef = sym.idRef();
    const IdentifierManager& idMgr = sema.idMgr();

    const SpecOpKind kind = sym.specOpKind();
    if (kind == SpecOpKind::None)
        return Result::Continue;
    if (kind == SpecOpKind::Invalid)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_spec_op_unknown, sym);
        diag.addNote(DiagnosticId::sema_note_spec_op_reserved);
        diag.report(sema.ctx());
        return Result::Error;
    }

    const std::string_view name = idMgr.get(idRef).name;
    if (kind == SpecOpKind::OpVisit && name.size() > std::string_view("opVisit").size())
    {
        const char variantStart = name[std::string_view("opVisit").size()];
        if (std::isupper(static_cast<unsigned char>(variantStart)) == 0)
            return reportSpecOpError(sema, sym, kind);
    }

    const SymbolStruct* ownerStruct = sym.ownerStruct();
    if (!ownerStruct)
        return SemaError::raise(sema, DiagnosticId::sema_err_spec_op_outside_impl, sym);
    const SymbolMap* ownerMap = sym.ownerSymMap();
    if (ownerMap && ownerMap->isImpl() && ownerMap->cast<SymbolImpl>().isForInterface())
        return SemaError::raise(sema, DiagnosticId::sema_err_spec_op_in_impl_for, sym);
    if ((sym.isGenericRoot() && !sym.isGenericInstance()) || (ownerStruct->isGenericRoot() && !ownerStruct->isGenericInstance()))
    {
        if (!hasSpecOpGenericSignature(sema, sym, kind))
        {
            if (kind == SpecOpKind::OpVisit)
                return Result::Continue;
            return reportSpecOpError(sema, sym, kind);
        }
        return Result::Continue;
    }

    return validateSpecOpSignature(sema, *ownerStruct, sym, kind);
}

Result SemaSpecOp::registerSymbol(Sema& sema, SymbolFunction& sym)
{
    const SpecOpKind kind = sym.specOpKind();
    if (kind == SpecOpKind::None)
        return Result::Continue;
    if (kind == SpecOpKind::Invalid)
        return Result::Continue;

    SymbolStruct* ownerStruct = sym.ownerStruct();
    if (!ownerStruct)
        return Result::Continue;

    const auto here = ownerStruct->getSpecOp(sym.idRef());
    if (std::ranges::find(here, &sym) != here.end())
        return Result::Continue;

    if (!allowsSpecOpOverload(kind))
    {
        if (!here.empty())
            return SemaError::raiseAlreadyDefined(sema, &sym, here.front());
    }

    return ownerStruct->registerSpecOp(sym, kind);
}

SpecOpKind SemaSpecOp::computeSymbolKind(const Sema& sema, const SymbolFunction& sym)
{
    const IdentifierRef      idRef = sym.idRef();
    const IdentifierManager& idMgr = sema.idMgr();

    const std::string_view name = idMgr.get(idRef).name;
    if (!LangSpec::isSpecOpName(name))
        return SpecOpKind::None;

    auto kind = SpecOpKind::Invalid;
    using Pn  = IdentifierManager::PredefinedName;
    struct Entry
    {
        Pn         pn;
        SpecOpKind kind;
    };

    static constexpr Entry K_MAP[] = {
        {Pn::OpVisit, SpecOpKind::OpVisit},
        {Pn::OpBinary, SpecOpKind::OpBinary},
        {Pn::OpBinaryRight, SpecOpKind::OpBinaryRight},
        {Pn::OpUnary, SpecOpKind::OpUnary},
        {Pn::OpAssign, SpecOpKind::OpAssign},
        {Pn::OpIndexAssign, SpecOpKind::OpIndexAssign},
        {Pn::OpCast, SpecOpKind::OpCast},
        {Pn::OpEquals, SpecOpKind::OpEquals},
        {Pn::OpCompare, SpecOpKind::OpCompare},
        {Pn::OpPostCopy, SpecOpKind::OpPostCopy},
        {Pn::OpPostMove, SpecOpKind::OpPostMove},
        {Pn::OpDrop, SpecOpKind::OpDrop},
        {Pn::OpCount, SpecOpKind::OpCount},
        {Pn::OpData, SpecOpKind::OpData},
        {Pn::OpSet, SpecOpKind::OpSet},
        {Pn::OpSetLiteral, SpecOpKind::OpSetLiteral},
        {Pn::OpSlice, SpecOpKind::OpSlice},
        {Pn::OpIndex, SpecOpKind::OpIndex},
        {Pn::OpIndexSet, SpecOpKind::OpIndexSet},
    };

    for (const auto& e : K_MAP)
    {
        if (idRef == idMgr.predefined(e.pn))
        {
            kind = e.kind;
            return kind;
        }
    }

    if (LangSpec::isOpVisitName(name))
        return SpecOpKind::OpVisit;
    return SpecOpKind::Invalid;
}


SWC_END_NAMESPACE();
