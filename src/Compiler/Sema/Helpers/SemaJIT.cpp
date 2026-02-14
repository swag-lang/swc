#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result getOrCreateRunExprSymbol(Sema& sema, SymbolFunction*& outSymFn, AstNodeRef nodeExprRef)
    {
        auto&            ctx     = sema.ctx();
        const AstNodeRef nodeRef = sema.curNodeRef();

        if (sema.hasSymbol(nodeRef))
        {
            outSymFn = &sema.symbolOf(nodeRef).cast<SymbolFunction>();
            return Result::Continue;
        }

        const SemaNodeView  nodeView(sema, nodeExprRef);
        const IdentifierRef idRef = SemaHelpers::getUniqueIdentifier(sema, "__run_expr");
        const AstNode&      node  = sema.node(nodeRef);

        outSymFn = Symbol::make<SymbolFunction>(ctx, &node, node.tokRef(), idRef, sema.frame().flagsForCurrentAccess());
        outSymFn->setOwnerSymMap(SemaFrame::currentSymMap(sema));
        outSymFn->setReturnTypeRef(nodeView.typeRef);
        outSymFn->setDeclared(ctx);
        outSymFn->setTyped(ctx);

        sema.setSymbol(nodeRef, outSymFn);

        const auto job = heapNew<CodeGenJob>(ctx, sema, *outSymFn, nodeRef);
        sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        return Result::Continue;
    }
}

Result SemaJIT::runExpr(Sema& sema, AstNodeRef nodeExprRef)
{
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));

    auto&            ctx     = sema.ctx();
    const AstNodeRef nodeRef = sema.curNodeRef();

    SymbolFunction* symFn = nullptr;
    RESULT_VERIFY(getOrCreateRunExprSymbol(sema, symFn, nodeExprRef));
    SWC_ASSERT(symFn != nullptr);

    RESULT_VERIFY(sema.waitCodeGenCompleted(symFn, sema.node(nodeRef).codeRef()));

    const SemaNodeView nodeView(sema, nodeExprRef);

    MicroInstrBuilder& builder = symFn->microInstrBuilder(ctx);
    builder.printInstructions();

    JITExecMemory executableMemory;
    RESULT_VERIFY(JIT::compile(ctx, builder, executableMemory));

    auto targetFn = executableMemory.entryPoint<void*>();
    SWC_ASSERT(targetFn != nullptr);

    const TypeInfo& nodeType         = *nodeView.type;
    TypeRef         resultStorageRef = nodeView.typeRef;
    if (nodeType.isEnum())
        resultStorageRef = nodeType.payloadSymEnum().underlyingTypeRef();
    else if (nodeType.isAlias())
        resultStorageRef = nodeType.payloadSymAlias().underlyingTypeRef();

    RESULT_VERIFY(sema.waitSemaCompleted(nodeView.type, nodeExprRef));

    const uint64_t         resultSize = sema.typeMgr().get(resultStorageRef).sizeOf(ctx);
    std::vector<std::byte> resultStorage(resultSize == 0 ? 1 : resultSize);

    const FFIReturn returnValue = {
        .typeRef  = nodeView.typeRef,
        .valuePtr = resultStorage.data(),
    };

    FFI::call(ctx, targetFn, std::span<const FFIArgument>{}, returnValue);

    ConstantValue resultConstant;
    if (nodeType.isEnum())
    {
        ConstantValue     enumStorage    = ConstantValue::make(ctx, resultStorage.data(), resultStorageRef);
        const ConstantRef enumStorageRef = sema.cstMgr().addConstant(ctx, enumStorage);
        resultConstant                   = ConstantValue::makeEnumValue(ctx, enumStorageRef, nodeView.typeRef);
    }
    else
    {
        resultConstant = ConstantValue::make(ctx, resultStorage.data(), nodeView.typeRef);
    }

    sema.setConstant(nodeExprRef, sema.cstMgr().addConstant(ctx, resultConstant));
    return Result::Continue;
}

SWC_END_NAMESPACE();
