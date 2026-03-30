#include "pch.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
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
            case SpecOpKind::None:
            case SpecOpKind::Invalid:
            default:
                return "valid special function signature";
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

    CodeGenNodePayload& ensureCodeGenNodePayload(Sema& sema, AstNodeRef nodeRef)
    {
        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(nodeRef);
        if (payload)
            return *payload;

        payload = sema.compiler().allocate<CodeGenNodePayload>();
        sema.setCodeGenPayload(nodeRef, payload);
        return *payload;
    }

    Result completeRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        if (auto* ownerFunction = sema.currentFunction(); ownerFunction && typeRef.isValid())
        {
            const TypeInfo& symType = sema.typeMgr().get(typeRef);
            SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            ownerFunction->addLocalVariable(sema.ctx(), &symVar);
        }

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SymbolVariable& registerUniqueRuntimeStorageSymbol(Sema& sema, const AstNode& node, std::string_view privateName)
    {
        TaskContext&        ctx         = sema.ctx();
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();
        auto*               symVariable = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);

        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(symVariable);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, symVariable, true);
        }

        return *symVariable;
    }

    Result attachRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, TypeRef storageTypeRef)
    {
        const auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (payload && payload->runtimeStorageSym != nullptr)
            return Result::Continue;
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
        {
            ensureCodeGenNodePayload(sema, sema.curNodeRef()).runtimeStorageSym = boundStorage;
            return Result::Continue;
        }

        auto& storageSym = registerUniqueRuntimeStorageSymbol(sema, node, "__spec_op_runtime_storage");
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT(Match::ghosting(sema, storageSym));
        SWC_RESULT(completeRuntimeStorageSymbol(sema, storageSym, storageTypeRef));

        ensureCodeGenNodePayload(sema, sema.curNodeRef()).runtimeStorageSym = &storageSym;
        return Result::Continue;
    }

    TypeRef syntheticCallRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn)
    {
        if (sema.isGlobalScope())
            return TypeRef::invalid();

        const TypeRef returnTypeRef = calledFn.returnTypeRef();
        if (!returnTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        if (returnType.isVoid())
            return TypeRef::invalid();

        const CallConv&                        callConv      = CallConv::get(calledFn.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(sema.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
        if (!normalizedRet.isIndirect)
            return TypeRef::invalid();

        const TypeRef storageTypeRef = returnType.unwrap(sema.ctx(), returnTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (storageTypeRef.isValid())
            return storageTypeRef;

        return returnTypeRef;
    }

    AstNodeRef makeSyntheticStringConstantArg(Sema& sema, const SourceCodeRef& codeRef, std::string_view value)
    {
        const auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::StringLiteral>(codeRef.tokRef);
        nodePtr->setCodeRef(codeRef);

        const TaskContext&  ctx         = sema.ctx();
        const ConstantValue constant    = ConstantValue::makeString(ctx, value);
        const ConstantRef   constantRef = sema.cstMgr().addConstant(ctx, constant);
        sema.setType(nodeRef, sema.typeMgr().typeString());
        sema.setConstant(nodeRef, constantRef);
        sema.setIsValue(*nodePtr);
        return nodeRef;
    }

    bool canExplicitlySpecializeSpecOp(Sema& sema, const SymbolFunction& symFunc, std::span<const AstNodeRef> genericArgNodes)
    {
        if (!symFunc.isGenericRoot() || genericArgNodes.empty())
            return false;

        const auto* decl = symFunc.decl() ? symFunc.decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!decl || !decl->spanGenericParamsRef.isValid())
            return false;

        std::vector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, decl->spanGenericParamsRef, params);
        if (genericArgNodes.size() > params.size())
            return false;

        for (size_t i = 0; i < genericArgNodes.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Value)
                return false;
        }

        return true;
    }

    Result collectSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();

        for (const SymbolImpl* symImpl : ownerStruct.impls())
        {
            if (!symImpl)
                continue;

            for (SymbolFunction* symFunc : symImpl->specOps())
            {
                if (!symFunc || symFunc->idRef() != idRef)
                    continue;

                if (!canExplicitlySpecializeSpecOp(sema, *symFunc, genericArgNodes))
                {
                    outCandidates.push_back(symFunc);
                    continue;
                }

                SymbolFunction* specialized = nullptr;
                SWC_RESULT(SemaGeneric::instantiateFunctionExplicit(sema, *symFunc, genericArgNodes, specialized));
                if (specialized)
                    outCandidates.push_back(specialized);
            }
        }

        return Result::Continue;
    }

    Result resolveSyntheticCall(Sema& sema, const AstNode& node, std::span<Symbol*> candidates, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        SmallVector<ResolvedCallArgument> resolvedArgs;
        const SemaNodeView                calleeView(sema, sema.curNodeRef(), SemaNodeViewPartE::Node);
        SWC_RESULT(Match::resolveFunctionCandidates(sema, calleeView, candidates, args, ufcsArg, &resolvedArgs));
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);

        auto& calledFn = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        SemaHelpers::addCurrentFunctionCallDependency(sema, &calledFn);

        SWC_RESULT(SemaJIT::tryRunConstCall(sema, calledFn, sema.curNodeRef(), resolvedArgs.span()));
        if (sema.viewConstant(sema.curNodeRef()).hasConstant())
            return Result::Continue;

        SWC_RESULT(SemaInline::tryInlineCall(sema, sema.curNodeRef(), calledFn, args, ufcsArg));
        SWC_RESULT(attachRuntimeStorageIfNeeded(sema, node, syntheticCallRuntimeStorageTypeRef(sema, calledFn)));
        return Result::Continue;
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
        TaskContext&       ctx     = sema.ctx();
        const TypeManager& typeMgr = sema.typeMgr();
        const auto&        params  = sym.parameters();

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

        auto requireReturnVoid = [&]() -> bool {
            return returnType.isVoid();
        };

        auto requireReturnNotVoid = [&]() -> bool {
            return !returnType.isVoid();
        };

        auto requireReturnType = [&](TypeRef typeRef) -> bool {
            return unwrapAlias(ctx, typeRef) == returnTypeRef;
        };

        auto requireReturnStruct = [&]() -> bool {
            return returnType.isStruct() && &returnType.payloadSymStruct() == &owner;
        };

        auto requireReturnPointer = [&]() -> bool {
            return returnType.isAnyPointer();
        };

        auto requireReturnStringOrSlice = [&]() -> bool {
            return returnType.isString() || returnType.isSlice();
        };

        auto requireU64Param = [&](size_t index) -> bool {
            return unwrapAlias(ctx, params[index]->typeRef()) == unwrapAlias(ctx, typeMgr.typeU64());
        };

        auto requireSecondNotStruct = [&]() -> bool {
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
            case SpecOpKind::None:
                return Result::Continue;
            case SpecOpKind::Invalid:
                return reportSpecOpError(sema, sym, kind);
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

    bool isSpecOpInImplFor(const SymbolFunction& sym)
    {
        const SymbolMap* symMap = sym.ownerSymMap();
        if (!symMap)
            return false;
        if (!symMap->isImpl())
            return false;
        return symMap->cast<SymbolImpl>().isForInterface();
    }

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
    if (isSpecOpInImplFor(sym))
        return SemaError::raise(sema, DiagnosticId::sema_err_spec_op_in_impl_for, sym);
    if (sym.isGenericInstance() && sym.genericRootSym() && sym.genericRootSym()->specOpKind() == kind)
        return Result::Continue;

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

    if (!allowsSpecOpOverload(kind))
    {
        const auto here = ownerStruct->getSpecOp(sym.idRef());
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
            kind = e.kind;
            return kind;
        }
    }

    if (LangSpec::isOpVisitName(name))
        return SpecOpKind::OpVisit;
    return SpecOpKind::Invalid;
}

Result SemaSpecOp::tryResolveUnary(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& operandView, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!tok.isAny({TokenId::SymPlus, TokenId::SymMinus, TokenId::SymBang, TokenId::SymTilde}))
        return Result::Continue;

    if (!operandView.type())
        return Result::Continue;

    TypeRef unwrappedTypeRef = unwrapAlias(sema.ctx(), operandView.typeRef());
    if (!unwrappedTypeRef.isValid())
        unwrappedTypeRef = operandView.typeRef();

    const TypeInfo& operandType = sema.typeMgr().get(unwrappedTypeRef);
    if (!operandType.isStruct())
        return Result::Continue;

    const auto& ownerStruct = operandType.payloadSymStruct();
    SWC_RESULT(sema.waitSemaCompleted(&ownerStruct, node.codeRef()));

    const SourceView&      srcView    = sema.compiler().srcView(node.srcViewRef());
    const std::string_view opString   = tok.string(srcView);
    const AstNodeRef       genericArg = makeSyntheticStringConstantArg(sema, node.codeRef(), opString);
    const IdentifierRef    opUnaryId  = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpUnary);
    SmallVector<Symbol*>   candidates;
    SWC_RESULT(collectSpecOpCandidates(sema, ownerStruct, opUnaryId, std::span{&genericArg, 1}, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeExprRef));
    outHandled = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
