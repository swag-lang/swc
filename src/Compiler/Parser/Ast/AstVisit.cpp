#include "pch.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

void AstVisit::resetFrame(Frame& frame, AstNodeRef nodeRef)
{
    frame.node         = nullptr;
    frame.nodeRef      = nodeRef;
    frame.stage        = Frame::Stage::Pre;
    frame.nextChildIx  = 0;
    frame.firstChildIx = 0;
    frame.numChildren  = 0;

    frame.firstPass = true;

    frame.preNodeState  = Frame::CallState::NotCalled;
    frame.postNodeState = Frame::CallState::NotCalled;

    frame.pendingPostChild = false;
    frame.postChildState   = Frame::CallState::NotCalled;
    frame.preChildState    = Frame::CallState::NotCalled;
}

void AstVisit::start(Ast& ast, AstNodeRef root)
{
    SWC_ASSERT(root.isValid());

    ast_     = &ast;
    rootRef_ = root;

    stack_.clear();
    children_.clear();

    Frame fr;
    resetFrame(fr, root);
    stack_.push_back(fr);
}

void AstVisit::restartCurrentNode(AstNodeRef nodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(!stack_.empty());
    resetFrame(stack_.back(), nodeRef);
}

AstVisitResult AstVisit::step(const TaskContext& ctx)
{
    if (stack_.empty())
        return AstVisitResult::Error;

    Frame& frame = stack_.back();

#if SWC_HAS_VISIT_DEBUG_INFO
    dbgNode    = &ast_->node(frame.nodeRef);
    dbgTokRef  = dbgNode->tokRef();
    dbgTok     = dbgTokRef.isValid() ? &ast_->srcView().token(dbgTokRef) : nullptr;
    dbgTokView = dbgTok ? dbgTok->string(ast_->srcView()) : "";
    dbgSrcFile = ast_->srcView().file();
    dbgLoc     = dbgTok ? dbgTok->codeRange(ctx, ast_->srcView()) : SourceCodeRange{};
#endif

    switch (frame.stage)
    {
        case Frame::Stage::Pre:
            return stepPreStage(frame);
        case Frame::Stage::Children:
            return stepChildrenStage(frame);
        case Frame::Stage::Post:
            return stepPostStage(frame);
    }

    SWC_UNREACHABLE();
}

AstVisitResult AstVisit::stepPreStage(Frame& frame)
{
    if (frame.node == nullptr)
    {
        SWC_ASSERT(frame.nodeRef.isValid());
        frame.node = &ast_->node(frame.nodeRef);
        SWC_ASSERT(frame.node->isNot(AstNodeId::Invalid));
        SWC_ASSERT(frame.node->id() < AstNodeId::Count);

#if SWC_HAS_STATS
        Stats::get().numVisitedAstNodes.fetch_add(1);
#endif
    }

    if (preNodeVisitor_ && frame.preNodeState != Frame::CallState::Done)
    {
        frame.firstPass     = (frame.preNodeState == Frame::CallState::NotCalled);
        const Result result = preNodeVisitor_(*frame.node);

        if (result == Result::Error)
            return AstVisitResult::Error;
        if (result == Result::Pause)
        {
            frame.preNodeState = Frame::CallState::Paused;
            return AstVisitResult::Pause;
        }

        frame.preNodeState = Frame::CallState::Done;

        if (result == Result::SkipChildren)
        {
            frame.stage = Frame::Stage::Post;
            return AstVisitResult::Continue;
        }
    }

    collectChildren(frame);

    frame.preChildState    = Frame::CallState::NotCalled;
    frame.pendingPostChild = false;
    frame.postChildState   = Frame::CallState::NotCalled;

    frame.stage = Frame::Stage::Children;
    return AstVisitResult::Continue;
}

AstVisitResult AstVisit::stepChildrenStage(Frame& frame)
{
    while (true)
    {
        if (frame.pendingPostChild)
        {
            if (postChildVisitor_ && frame.postChildState != Frame::CallState::Done)
            {
                SWC_ASSERT(frame.nextChildIx > 0);
                AstNodeRef callbackRef = children_[frame.firstChildIx + frame.nextChildIx - 1];

                frame.firstPass     = (frame.postChildState == Frame::CallState::NotCalled);
                const Result result = postChildVisitor_(*frame.node, callbackRef);

                if (result == Result::Error)
                    return AstVisitResult::Error;
                if (result == Result::Pause)
                {
                    frame.postChildState = Frame::CallState::Paused;
                    return AstVisitResult::Pause;
                }

                frame.postChildState = Frame::CallState::Done;
            }

            frame.pendingPostChild = false;
            frame.postChildState   = Frame::CallState::NotCalled;
            continue;
        }

        if (frame.nextChildIx >= frame.numChildren)
            break;

        const uint32_t localIdx = frame.nextChildIx;
        const uint32_t globalIx = frame.firstChildIx + localIdx;

        AstNodeRef childRef = children_[globalIx];

        if (preChildVisitor_ && frame.preChildState != Frame::CallState::Done)
        {
            frame.firstPass     = (frame.preChildState == Frame::CallState::NotCalled);
            const Result result = preChildVisitor_(*frame.node, childRef);

            if (result == Result::Error)
                return AstVisitResult::Error;
            if (result == Result::Pause)
            {
                frame.preChildState = Frame::CallState::Paused;
                return AstVisitResult::Pause;
            }

            frame.preChildState = Frame::CallState::Done;

            if (result == Result::SkipChildren)
            {
                frame.nextChildIx++;
                frame.preChildState = Frame::CallState::NotCalled;
                continue;
            }
        }

        if (childRef.isInvalid())
        {
            frame.nextChildIx++;
            frame.preChildState = Frame::CallState::NotCalled;
            continue;
        }

        Frame childFrame;
        resetFrame(childFrame, childRef);
        stack_.push_back(childFrame);

        frame.nextChildIx++;
        frame.pendingPostChild = true;
        frame.postChildState   = Frame::CallState::NotCalled;
        frame.preChildState    = Frame::CallState::NotCalled;

        return AstVisitResult::Continue;
    }

    frame.stage = Frame::Stage::Post;
    return AstVisitResult::Continue;
}

AstVisitResult AstVisit::stepPostStage(Frame& frame)
{
    if (postNodeVisitor_ && frame.postNodeState != Frame::CallState::Done)
    {
        frame.firstPass     = (frame.postNodeState == Frame::CallState::NotCalled);
        const Result result = postNodeVisitor_(*frame.node);

        if (result == Result::Error)
        {
            return AstVisitResult::Error;
        }

        if (result == Result::Pause)
        {
            frame.postNodeState = Frame::CallState::Paused;
            return AstVisitResult::Pause;
        }

        if (frame.stage != Frame::Stage::Post)
        {
            return AstVisitResult::Continue;
        }

        frame.postNodeState = Frame::CallState::Done;
    }

    stack_.pop_back();
    if (stack_.empty())
        return AstVisitResult::Stop;

    return AstVisitResult::Continue;
}

void AstVisit::collectChildren(Frame& frame)
{
    const AstNodeIdInfo& info = Ast::nodeIdInfos(frame.node->id());
    frame.firstChildIx        = children_.size32();
    info.collectChildren(children_, *ast_, *frame.node);
    frame.numChildren = children_.size32() - frame.firstChildIx;
    frame.nextChildIx = 0;

    if (mode_ != AstVisitMode::ResolveBeforeCallbacks || !nodeRefResolver_)
        return;

    const uint32_t childStart = frame.firstChildIx;
    const uint32_t childEnd   = frame.firstChildIx + frame.numChildren;
    for (uint32_t i = childStart; i < childEnd; i++)
    {
        const AstNodeRef childRef = children_[i];
        if (childRef.isInvalid())
            continue;

        const AstNodeRef resolvedRef = nodeRefResolver_(childRef);
        if (resolvedRef.isInvalid() || resolvedRef == frame.nodeRef)
            continue;

        children_[i] = resolvedRef;
    }
}

AstNode* AstVisit::parentNodeInternal(size_t up) const
{
    if (stack_.size() <= 1)
        return nullptr;

    const size_t selfIdx = stack_.size() - 1;
    if (up >= selfIdx)
        return nullptr;

    const Frame& fr = stack_[selfIdx - 1 - up];
    return fr.node;
}

AstNodeRef AstVisit::parentNodeRefInternal(size_t up) const
{
    if (stack_.size() <= 1)
        return AstNodeRef::invalid();

    const size_t selfIdx = stack_.size() - 1;
    if (up >= selfIdx)
        return AstNodeRef::invalid();

    const Frame& fr = stack_[selfIdx - 1 - up];
    return fr.nodeRef;
}

SWC_END_NAMESPACE();
