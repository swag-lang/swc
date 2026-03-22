#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    CodeGenNodePayload& ensureCodeGenNodePayload(Sema& sema, AstNodeRef nodeRef)
    {
        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(nodeRef);
        if (payload)
            return *payload;

        payload = sema.compiler().allocate<CodeGenNodePayload>();
        sema.setCodeGenPayload(nodeRef, payload);
        return *payload;
    }

    SymbolVariable& getOrCreateCastRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        auto& payload = ensureCodeGenNodePayload(sema, sema.curNodeRef());
        if (payload.runtimeStorageSym != nullptr)
            return *payload.runtimeStorageSym;

        if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
        {
            payload.runtimeStorageSym = boundStorage;
            return *boundStorage;
        }

        TaskContext&        ctx         = sema.ctx();
        const Utf8          privateName = "__cast_runtime_storage";
        const IdentifierRef idRef       = sema.idMgr().addIdentifierOwned(std::format("{}_{}", privateName, sema.compiler().atomicId().fetch_add(1)));
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();

        auto* sym = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(sym);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, sym, true);
        }

        payload.runtimeStorageSym = sym;
        return *sym;
    }

    Result completeCastRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, symVar, typeRef));

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    TypeRef castRuntimeStorageTypeRef(Sema& sema, const SemaNodeView& srcView, const SemaNodeView& dstView)
    {
        if (!srcView.type() || !dstView.type())
            return TypeRef::invalid();
        if (srcView.hasConstant())
            return TypeRef::invalid();

        if (srcView.type()->isArray() && (dstView.type()->isSlice() || dstView.type()->isString()))
            return dstView.typeRef();

        if (!srcView.type()->isAny() && dstView.type()->isAny())
        {
            constexpr uint64_t     anyStorageSize = sizeof(Runtime::Any);
            const uint64_t         valueStorage   = srcView.type()->sizeOf(sema.ctx());
            SmallVector4<uint64_t> dims;
            dims.push_back(anyStorageSize + valueStorage);
            return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
        }

        if (srcView.type()->isStruct() && dstView.type()->isInterface())
        {
            constexpr uint64_t     interfaceStorageSize = sizeof(Runtime::Interface);
            const uint64_t         valueStorage         = srcView.type()->sizeOf(sema.ctx());
            SmallVector4<uint64_t> dims;
            dims.push_back(interfaceStorageSize + valueStorage);
            return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
        }

        if (srcView.type()->isFunction() && dstView.type()->isFunction() && !srcView.type()->isLambdaClosure() && dstView.type()->isLambdaClosure())
            return dstView.typeRef();

        return TypeRef::invalid();
    }

    Result retargetLiteralRuntimeStorageIfNeeded(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef.isInvalid() || dstTypeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        const bool      needsRetarget =
            (srcType.isAggregateArray() && dstType.isArray()) ||
            (srcType.isAggregateStruct() && dstType.isStruct());
        if (!needsRetarget)
            return Result::Continue;

        const auto* payload = sema.codeGenPayload<CodeGenNodePayload>(nodeRef);
        if (!payload || payload->runtimeStorageSym == nullptr)
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(&dstType, nodeRef));
        payload->runtimeStorageSym->setTypeRef(dstTypeRef);
        return Result::Continue;
    }
}

Result AstSuffixLiteral::semaPostNode(Sema& sema) const
{
    const TaskContext& ctx        = sema.ctx();
    const SemaNodeView suffixView = sema.viewType(nodeSuffixRef);
    const TypeRef      typeRef    = suffixView.typeRef();
    sema.setType(sema.curNodeRef(), typeRef);
    sema.setIsValue(sema.curNodeRef());

    SemaNodeView nodeLiteralView = sema.viewNodeTypeConstant(nodeLiteralRef);
    SWC_ASSERT(nodeLiteralView.cstRef().isValid());

    ConstantRef cstRef = nodeLiteralView.cstRef();

    // Special case for negation: we need to negate before casting, in order for -128's8 to compile, for example.
    // @MinusLiteralSuffix
    if (const auto* parentNode = sema.visit().parentNode(); parentNode->is(AstNodeId::UnaryExpr))
    {
        const Token& tok = sema.token(parentNode->codeRef());
        if (tok.is(TokenId::SymMinus))
        {
            const ConstantValue& cst  = sema.cstMgr().get(cstRef);
            const TypeInfo&      type = sema.typeMgr().get(cst.typeRef());
            if (type.isInt())
            {
                ApsInt cpy = cst.getInt();

                bool overflow = false;
                cpy.negate(overflow);
                if (overflow)
                    return SemaError::raiseLiteralOverflow(sema, nodeLiteralRef, cst, cst.typeRef());
                cpy.setUnsigned(false);
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpy, cst.type(ctx).payloadIntBits(), TypeInfo::Sign::Signed));
            }
            else if (type.isFloat())
            {
                ApFloat cpy = cst.getFloat();
                cpy.negate();
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, cpy, cst.type(ctx).payloadFloatBits()));
            }
        }
    }

    sema.setConstant(nodeLiteralView.nodeRef(), cstRef);
    nodeLiteralView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
    SWC_RESULT(Cast::cast(sema, nodeLiteralView, typeRef, CastKind::LiteralSuffix));
    sema.setConstant(sema.curNodeRef(), nodeLiteralView.cstRef());

    return Result::Continue;
}

Result AstCastExpr::semaPostNode(Sema& sema)
{
    if (!hasFlag(AstCastExprFlagsE::Explicit))
        return Result::Continue;

    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView srcTypeView  = sema.viewTypeConstant(nodeExprRef);
    const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);

    // Value-check
    SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    // Check cast modifiers
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst));

    // Cast kind
    CastFlags castFlags = CastFlagsE::Zero;
    if (modifierFlags.has(AstModifierFlagsE::Bit))
        castFlags.add(CastFlagsE::BitCast);
    if (modifierFlags.has(AstModifierFlagsE::UnConst))
        castFlags.add(CastFlagsE::UnConst);
    castFlags.add(CastFlagsE::FromExplicitNode);

    sema.inheritPayload(*this, nodeExprView.nodeRef());
    SemaNodeView view = sema.curViewNodeTypeConstant();
    view.typeRef()    = view.type()->unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Function);
    SWC_RESULT(Cast::cast(sema, view, nodeTypeView.typeRef(), CastKind::Explicit, castFlags));
    sema.setIsValue(*this);

    const SemaNodeView dstTypeView = sema.curViewType();
    SWC_RESULT(retargetLiteralRuntimeStorageIfNeeded(sema, nodeExprView.nodeRef(), srcTypeView.typeRef(), dstTypeView.typeRef()));
    const TypeRef runtimeStorageTypeRef = castRuntimeStorageTypeRef(sema, srcTypeView, dstTypeView);
    if (runtimeStorageTypeRef.isValid() && SemaHelpers::isCurrentFunction(sema))
    {
        auto& storageSym = getOrCreateCastRuntimeStorageSymbol(sema, *this);
        if (&storageSym == SemaHelpers::currentRuntimeStorage(sema))
            return Result::Continue;
        if (!storageSym.isDeclared())
        {
            storageSym.registerAttributes(sema);
            storageSym.setDeclared(sema.ctx());
        }

        if (!storageSym.isSemaCompleted())
        {
            SWC_RESULT(Match::ghosting(sema, storageSym));
            SWC_RESULT(completeCastRuntimeStorageSymbol(sema, storageSym, runtimeStorageTypeRef));
        }
    }

    return Result::Continue;
}

Result AstAutoCastExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);
    const SemaNodeView exprView     = sema.viewTypeConstant(nodeExprRef);

    // Value-check
    SWC_RESULT(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    // Check cast modifiers
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst));

    // We do not know the destination type here (it comes from context),
    // but we still need the source expression type or constant. Copying the raw payload would
    // keep a call's callee symbol payload and expose `func()->T` instead of the call result `T`.
    if (exprView.hasConstant())
        sema.setConstant(sema.curNodeRef(), exprView.cstRef());
    else
        sema.setType(sema.curNodeRef(), exprView.typeRef());

    if (sema.isFoldedTypedConst(nodeExprRef))
        sema.setFoldedTypedConst(sema.curNodeRef());

    sema.setIsValue(*this);

    return Result::Continue;
}

SWC_END_NAMESPACE();
