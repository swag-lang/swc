#include "pch.h"
#include "Backend/Sanitizer/Checks/Check.FloatDomain.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Interprets a tracked constant's bits as a float of the given width. Returns false
    // when the width is not a float width.
    bool constantAsDouble(double& outValue, uint64_t bits, uint32_t floatBits)
    {
        if (floatBits == 32)
        {
            outValue = static_cast<double>(std::bit_cast<float>(static_cast<uint32_t>(bits)));
            return true;
        }

        if (floatBits == 64)
        {
            outValue = std::bit_cast<double>(bits);
            return true;
        }

        return false;
    }

    // The domain rules mirror the runtime guards (`emitUnaryMathDomainCheck`): a NaN
    // constant compares false everywhere and is conservatively not flagged.
    bool violatesLogDomain(double value)
    {
        return value < 0.0;
    }

    bool violatesArcDomain(double value)
    {
        return value < -1.0 || value > 1.0;
    }

    void checkMathIntrinsicCall(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        const Symbol* target = sanitizer.currentCallTarget();
        if (!target || !target->isFunction())
            return;

        const std::string_view name  = target->name(sanitizer.ctx());
        const bool             isLog = name == "@log" || name == "@log2" || name == "@log10";
        const bool             isArc = name == "@asin" || name == "@acos";
        if (!isLog && !isArc)
            return;

        // The checked value is the function's first parameter, marshalled into the call
        // convention's first float argument register.
        const SymbolFunction& fn = target->cast<SymbolFunction>();
        if (fn.parameters().empty())
            return;
        const TypeRef paramTypeRef = fn.parameters()[0]->typeRef();
        if (!paramTypeRef.isValid())
            return;
        const TypeInfo& paramType = sanitizer.ctx().typeMgr().get(paramTypeRef);
        if (!paramType.isFloat())
            return;

        const CallConv& callConv = CallConv::get(ops[0].callConv);
        if (callConv.floatArgRegs.empty())
            return;

        const SanitizerValue arg = sanitizer.getReg(state, callConv.floatArgRegs[0]);
        if (arg.kind != SanitizerValueKind::Constant)
            return;

        double value = 0.0;
        if (!constantAsDouble(value, arg.constant, paramType.payloadFloatBitsOr(64)))
            return;

        if ((isLog && violatesLogDomain(value)) || (isArc && violatesArcDomain(value)))
            sanitizer.report(inst, DiagnosticId::sanity_err_invalid_argument);
    }
}

void FloatDomainCheck::run(Sanitizer& sanitizer, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    if (!ops)
        return;

    // `sqrt` lowers inline: `reg = FloatSqrt(reg)`, ops = [dst, src, opBits, microOp].
    if (inst.op == MicroInstrOpcode::OpBinaryRegReg && ops[3].microOp == MicroOp::FloatSqrt)
    {
        const SanitizerValue operand = sanitizer.getReg(state, ops[1].reg);
        double               value   = 0.0;
        if (operand.kind == SanitizerValueKind::Constant &&
            constantAsDouble(value, operand.constant, static_cast<uint32_t>(ops[2].opBits)) &&
            value < 0.0)
            sanitizer.report(inst, DiagnosticId::sanity_err_invalid_argument);
        return;
    }

    // `log/log2/log10/asin/acos` lower to runtime calls: inspect the argument register.
    if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
        checkMathIntrinsicCall(sanitizer, state, inst, ops);
}

SWC_END_NAMESPACE();
