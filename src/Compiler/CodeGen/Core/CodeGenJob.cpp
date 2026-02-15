#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result extractSimpleFunctionReturnExpr(Sema& sema, const SymbolFunction& symbolFunc, AstNodeRef& outExprRef)
    {
        outExprRef = AstNodeRef::invalid();
        if (!symbolFunc.decl())
            return Result::Error;

        const auto* nodeDecl = symbolFunc.decl()->safeCast<AstFunctionDecl>();
        if (!nodeDecl)
            return Result::Error;

        if (nodeDecl->nodeBodyRef.isInvalid())
            return Result::Error;

        if (nodeDecl->hasFlag(AstFunctionFlagsE::Short))
        {
            outExprRef = nodeDecl->nodeBodyRef;
            return Result::Continue;
        }

        const auto* body = sema.node(nodeDecl->nodeBodyRef).safeCast<AstEmbeddedBlock>();
        if (!body)
            return Result::Error;

        SmallVector<AstNodeRef> statements;
        sema.ast().appendNodes(statements, body->spanChildrenRef);
        if (statements.size() != 1)
            return Result::Error;

        const auto* returnStmt = sema.node(statements.front()).safeCast<AstReturnStmt>();
        if (!returnStmt || returnStmt->nodeExprRef.isInvalid())
            return Result::Error;

        outExprRef = returnStmt->nodeExprRef;
        return Result::Continue;
    }

    Result emitSimpleFunctionRet(Sema& sema, CodeGen& codeGen, SymbolFunction& symbolFunc, AstNodeRef exprRef)
    {
        const auto* exprPayload = codeGen.payload(exprRef);
        if (!exprPayload)
            return Result::Error;

        const CallConvKind callConvKind  = symbolFunc.callConvKind();
        const CallConv&    callConv      = CallConv::get(callConvKind);
        const TypeRef      returnTypeRef = symbolFunc.returnTypeRef();
        const auto         normalizedRet = ABITypeNormalize::normalize(sema.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);

        if (normalizedRet.isVoid)
        {
            symbolFunc.microInstrBuilder(sema.ctx()).encodeRet(EncodeFlagsE::Zero);
            return Result::Continue;
        }

        if (normalizedRet.isIndirect)
            return Result::Error;

        const MicroOpBits retBits = normalizedRet.numBits ? microOpBitsFromBitWidth(normalizedRet.numBits) : MicroOpBits::B64;
        if (retBits == MicroOpBits::Zero)
            return Result::Error;

        auto&        builder = symbolFunc.microInstrBuilder(sema.ctx());
        const MicroReg srcReg  = exprPayload->reg;
        if (normalizedRet.isFloat)
            builder.encodeLoadRegReg(callConv.floatReturn, srcReg, retBits, EncodeFlagsE::Zero);
        else
            builder.encodeLoadRegReg(callConv.intReturn, srcReg, retBits, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);
        return Result::Continue;
    }

    Result generateFunctionCodeGen(Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root)
    {
        if (!root.isValid())
            return Result::Error;

        const AstNode& rootNode = sema.node(root);
        if (!rootNode.is(AstNodeId::FunctionDecl))
        {
            CodeGen codeGen(sema);
            return codeGen.exec(symbolFunc, root);
        }

        AstNodeRef exprRef = AstNodeRef::invalid();
        RESULT_VERIFY(extractSimpleFunctionReturnExpr(sema, symbolFunc, exprRef));

        CodeGen codeGen(sema);
        RESULT_VERIFY(codeGen.exec(symbolFunc, exprRef));
        return emitSimpleFunctionRet(sema, codeGen, symbolFunc, exprRef);
    }
}

CodeGenJob::CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root) :
    Job(ctx, JobKind::CodeGen),
    sema_(&sema),
    symbolFunc_(&symbolFunc),
    root_(root)
{
    func = [this] {
        return exec();
    };
}

JobResult CodeGenJob::exec()
{
    SWC_ASSERT(sema_);
    SWC_ASSERT(symbolFunc_);

    if (!symbolFunc_->isSemaCompleted())
        return JobResult::Sleep;

    SmallVector<SymbolFunction*> deps;
    symbolFunc_->appendCallDependencies(deps);

    if (deps.empty() && root_.isValid() && !sema_->node(root_).is(AstNodeId::FunctionDecl))
    {
        CodeGen      codeGen(*sema_);
        const Result result = codeGen.exec(*symbolFunc_, root_);
        if (result == Result::Continue)
        {
            symbolFunc_->setCodeGenCompleted(ctx());
            return JobResult::Done;
        }

        if (result == Result::Pause)
            return JobResult::Sleep;

        return JobResult::Done;
    }

    for (auto* dep : deps)
    {
        if (!dep)
            continue;

        if (!dep->isSemaCompleted())
            return JobResult::Sleep;

        if (dep->tryMarkCodeGenJobScheduled())
        {
            const AstNodeRef depRoot = dep->declNodeRef();
            if (!depRoot.isValid())
                continue;
            const auto depJob = heapNew<CodeGenJob>(ctx(), *sema_, *dep, depRoot);
            sema_->compiler().global().jobMgr().enqueue(*depJob, JobPriority::Normal, sema_->compiler().jobClientId());
        }
    }

    const Result result = generateFunctionCodeGen(*sema_, *symbolFunc_, root_);
    if (result == Result::Continue)
    {
        symbolFunc_->setCodeGenPreSolved(ctx());

        if (root_.isValid() && sema_->node(root_).is(AstNodeId::FunctionDecl))
            if (symbolFunc_->ensureJitEntry(ctx()) != Result::Continue)
                return JobResult::Done;

        bool depsReady = true;
        for (auto* dep : deps)
        {
            if (!dep)
                continue;
            if (!(dep->isCodeGenCompleted() || dep->isCodeGenPreSolved()))
            {
                depsReady = false;
                break;
            }
        }

        if (!depsReady)
            return JobResult::Sleep;

        symbolFunc_->setCodeGenCompleted(ctx());
        return JobResult::Done;
    }

    if (result == Result::Pause)
        return JobResult::Sleep;

    return JobResult::Done;
}

SWC_END_NAMESPACE();
