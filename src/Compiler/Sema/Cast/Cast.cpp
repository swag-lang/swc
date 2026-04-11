#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    AstNodeRef fallbackCastFailureNodeRef(Sema& sema, const CastFailure& failure)
    {
        if (failure.nodeRef.isValid())
            return failure.nodeRef;

        const AstNodeRef stateNodeRef = sema.ctx().state().nodeRef;
        if (stateNodeRef.isValid())
            return stateNodeRef;

        return sema.curNodeRef();
    }

}

TypeRef Cast::runtimeStorageTypeRef(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef)
{
    if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
        return TypeRef::invalid();

    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    if (srcConstRef.isValid())
    {
        if (dstType.isArray() && !srcType.isAggregate() && !srcType.isArray())
            return dstTypeRef;
        return TypeRef::invalid();
    }

    if (srcType.isArray() && (dstType.isSlice() || dstType.isString()))
        return dstTypeRef;

    if (!srcType.isAny() && dstType.isAny())
    {
        constexpr uint64_t     anyStorageSize = sizeof(Runtime::Any);
        const uint64_t         valueStorage   = srcType.sizeOf(sema.ctx());
        SmallVector4<uint64_t> dims;
        dims.push_back(anyStorageSize + valueStorage);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
    }

    if (srcType.isStruct() && dstType.isInterface())
    {
        constexpr uint64_t     interfaceStorageSize = sizeof(Runtime::Interface);
        const uint64_t         valueStorage         = srcType.sizeOf(sema.ctx());
        SmallVector4<uint64_t> dims;
        dims.push_back(interfaceStorageSize + valueStorage);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
    }

    if (srcType.isFunction() && dstType.isFunction() && !srcType.isLambdaClosure() && dstType.isLambdaClosure())
        return dstTypeRef;

    return TypeRef::invalid();
}

Result Cast::emitCastFailure(Sema& sema, const CastFailure& f)
{
    // Some callers propagate a pre-existing semantic error through the cast layer without
    // populating a cast-specific diagnostic. In that case, preserve the original failure.
    if (f.diagId == DiagnosticId::None)
        return Result::Error;

    Diagnostic diag;
    if (f.codeRef.isValid())
        diag = SemaError::report(sema, f.diagId, f.codeRef);
    else
    {
        const AstNodeRef errorNodeRef = fallbackCastFailureNodeRef(sema, f);
        if (errorNodeRef.isValid())
            diag = SemaError::report(sema, f.diagId, errorNodeRef);
        else
        {
            const SourceCodeRef stateCodeRef = sema.ctx().state().codeRef;
            SWC_ASSERT(stateCodeRef.isValid());
            diag = SemaError::report(sema, f.diagId, stateCodeRef);
        }
    }
    f.applyArguments(diag);
    if (f.noteId != DiagnosticId::None)
    {
        diag.addNote(f.noteId);
        f.applyArguments(diag.last());

        if (f.noteNodeRef.isValid())
        {
            diag.last().addSpan(sema.node(f.noteNodeRef).codeRangeWithChildren(sema.ctx(), sema.ast()));
        }
        else if (f.noteCodeRef.isValid())
        {
            const SourceView& srcView = sema.ctx().compiler().srcView(f.noteCodeRef.srcViewRef);
            diag.last().addSpan(srcView.tokenCodeRange(sema.ctx(), f.noteCodeRef.tokRef));
        }
    }
    diag.report(sema.ctx());
    return Result::Error;
}

Result Cast::attachCastRuntimeStorageIfNeeded(Sema& sema, AstNodeRef castNodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef)
{
    if (sema.isGlobalScope())
        return Result::Continue;

    const TypeRef storageTypeRef = Cast::runtimeStorageTypeRef(sema, srcTypeRef, dstTypeRef, srcConstRef);
    if (storageTypeRef.isInvalid())
        return Result::Continue;

    auto& storageSym = SemaHelpers::getOrCreateRuntimeStorageSymbol(sema, castNodeRef, sema.node(castNodeRef), "__cast_runtime_storage");
    return SemaHelpers::ensureRuntimeStorageDeclaredAndCompleted(sema, storageSym, storageTypeRef);
}

AstNodeRef Cast::createCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef, AstCastExprFlagsE castFlags)
{
    const AstNode& node               = sema.node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::CastExpr>(node.tokRef());
    substNodePtr->addFlag(castFlags);
    substNodePtr->nodeTypeRef = AstNodeRef::invalid();
    substNodePtr->nodeExprRef = nodeRef;
    sema.setSubstitute(nodeRef, substNodeRef);
    sema.setType(substNodeRef, dstTypeRef);
    sema.setIsValue(*substNodePtr);
    return substNodeRef;
}

SWC_END_NAMESPACE();
