#include "pch.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

TaskContext::TaskContext(const Global& global, const CommandLine& cmdLine) :
    global_(&global),
    cmdLine_(&cmdLine),
    editorService_(isEditorServiceCommand(cmdLine.command))
{
}

TaskContext::TaskContext(CompilerInstance& compInst) :
    compilerInstance_(&compInst)
{
    global_        = &compInst.global();
    cmdLine_       = &compInst.cmdLine();
    editorService_ = isEditorServiceCommand(cmdLine_->command);
}

TaskContext::TaskContext(const TaskContext& other) :
    global_(other.global_),
    cmdLine_(other.cmdLine_),
    compilerInstance_(other.compilerInstance_),
    silentDiagnostic_(other.silentDiagnostic_),
    reportToStats_(other.reportToStats_),
    muteOutput_(other.muteOutput_),
    hasError_(other.hasError_),
    hasWarning_(other.hasWarning_),
    editorService_(other.editorService_),
    state_(other.state_)
{
}

TaskContext& TaskContext::operator=(const TaskContext& other)
{
    if (this == &other)
        return *this;

    global_           = other.global_;
    cmdLine_          = other.cmdLine_;
    compilerInstance_ = other.compilerInstance_;
    silentDiagnostic_ = other.silentDiagnostic_;
    reportToStats_    = other.reportToStats_;
    muteOutput_       = other.muteOutput_;
    hasError_         = other.hasError_;
    hasWarning_       = other.hasWarning_;
    editorService_    = other.editorService_;
    state_            = other.state_;
    genericNodeRunCache_.reset();
    genericInstanceNodeRunCache_.reset();
    genericImplBlockRunCache_.reset();
    return *this;
}

ConstantManager& TaskContext::cstMgr()
{
    return compiler().cstMgr();
}

const ConstantManager& TaskContext::cstMgr() const
{
    return compiler().cstMgr();
}

TypeManager& TaskContext::typeMgr()
{
    return compiler().typeMgr();
}

const TypeManager& TaskContext::typeMgr() const
{
    return compiler().typeMgr();
}

TypeGen& TaskContext::typeGen()
{
    return compiler().typeGen();
}

const TypeGen& TaskContext::typeGen() const
{
    return compiler().typeGen();
}

IdentifierManager& TaskContext::idMgr()
{
    return compiler().idMgr();
}

const IdentifierManager& TaskContext::idMgr() const
{
    return compiler().idMgr();
}

void* TaskContext::allocate(size_t size, size_t alignment)
{
    return allocationArena().allocate(size, alignment);
}

Arena& TaskContext::allocationArena()
{
    return compiler().threadArena();
}

void TaskContext::notifyAlive()
{
    compiler().notifyAlive();
}

const TaskContext* TaskContext::setCurrent(const TaskContext* ctx) noexcept
{
    const TaskContext* previous = current_;
    current_                    = ctx;
    return previous;
}

SWC_END_NAMESPACE();
