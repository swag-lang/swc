#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Support/Report/Diagnostic.h"

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

    Result completeCastRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, symVar));

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    TypeRef castRuntimeStorageTypeRef(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef)
    {
        if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
            return TypeRef::invalid();
        if (srcConstRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

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

    SymbolVariable& registerUniqueCastRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        TaskContext&        ctx         = sema.ctx();
        const auto          privateName = Utf8("__cast_runtime_storage");
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

        return *(sym);
    }

    Result attachCastRuntimeStorageIfNeededImpl(Sema& sema, AstNodeRef castNodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef)
    {
        if (SemaHelpers::isGlobalScope(sema))
            return Result::Continue;

        const TypeRef storageTypeRef = castRuntimeStorageTypeRef(sema, srcTypeRef, dstTypeRef, srcConstRef);
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        auto& payload = ensureCodeGenNodePayload(sema, castNodeRef);
        if (payload.runtimeStorageSym == nullptr)
        {
            if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
                payload.runtimeStorageSym = boundStorage;
            else
            {
                auto& storageSym          = registerUniqueCastRuntimeStorageSymbol(sema, sema.node(castNodeRef));
                payload.runtimeStorageSym = &storageSym;
            }
        }

        auto& storageSym = *payload.runtimeStorageSym;
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
            SWC_RESULT(completeCastRuntimeStorageSymbol(sema, storageSym, storageTypeRef));
        }

        return Result::Continue;
    }
}

Result Cast::emitCastFailure(Sema& sema, const CastFailure& f)
{
    Diagnostic diag;
    if (f.codeRef.isValid())
        diag = SemaError::report(sema, f.diagId, f.codeRef);
    else
    {
        SWC_ASSERT(f.nodeRef.isValid());
        diag = SemaError::report(sema, f.diagId, f.nodeRef);
    }
    f.applyArguments(diag);
    diag.addNote(f.noteId);
    diag.report(sema.ctx());
    return Result::Error;
}

Result Cast::attachCastRuntimeStorageIfNeeded(Sema& sema, AstNodeRef castNodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef)
{
    return attachCastRuntimeStorageIfNeededImpl(sema, castNodeRef, srcTypeRef, dstTypeRef, srcConstRef);
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
