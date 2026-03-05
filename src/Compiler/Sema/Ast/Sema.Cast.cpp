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
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result completeCastRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        if (SymbolFunction* currentFunc = sema.frame().currentFunction())
        {
            const TypeInfo& symType = sema.typeMgr().get(typeRef);
            SWC_RESULT_VERIFY(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            currentFunc->addLocalVariable(sema.ctx(), &symVar);
        }

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

        return TypeRef::invalid();
    }
}

Result AstSuffixLiteral::semaPostNode(Sema& sema) const
{
    const TaskContext& ctx        = sema.ctx();
    const SemaNodeView suffixView = sema.viewType(nodeSuffixRef);
    const TypeRef      typeRef    = suffixView.typeRef();

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
    SWC_RESULT_VERIFY(Cast::cast(sema, nodeLiteralView, typeRef, CastKind::LiteralSuffix));
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
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    // Check cast modifiers
    SWC_RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst));

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
    SWC_RESULT_VERIFY(Cast::cast(sema, view, nodeTypeView.typeRef(), CastKind::Explicit, castFlags));
    sema.setIsValue(*this);

    const SemaNodeView dstTypeView           = sema.curViewType();
    const TypeRef      runtimeStorageTypeRef = castRuntimeStorageTypeRef(sema, srcTypeView, dstTypeView);
    if (runtimeStorageTypeRef.isValid() && sema.frame().currentFunction() != nullptr)
    {
        auto& storageSym = SemaHelpers::registerUniqueSymbol<SymbolVariable>(sema, *this, "cast_runtime_storage");
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT_VERIFY(Match::ghosting(sema, storageSym));
        SWC_RESULT_VERIFY(completeCastRuntimeStorageSymbol(sema, storageSym, runtimeStorageTypeRef));

        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeStorageSym = &storageSym;
    }

    return Result::Continue;
}

Result AstAutoCastExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.viewZero(nodeExprRef);

    // Value-check
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprView.nodeRef()));

    // Check cast modifiers
    SWC_RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst));

    // We do not know the destination type here (it comes from context).
    // Keep the node and inherit the child payload; the cast will be applied later.
    sema.inheritPayload(*this, nodeExprView.nodeRef());
    sema.setIsValue(*this);

    return Result::Continue;
}

SWC_END_NAMESPACE();
