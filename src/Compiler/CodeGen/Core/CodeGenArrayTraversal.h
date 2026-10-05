#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Math/ApInt.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenArrayTraversal
{
    template<typename EmitElement>
    inline Result emit(CodeGen& codeGen, MicroReg addressReg, const TypeInfo& type, EmitElement emitElement)
    {
        const TypeInfo& elementType = codeGen.typeMgr().get(type.payloadArrayElemTypeRef());
        const uint64_t  elementSize = elementType.sizeOf(codeGen.ctx());
        const uint64_t  count       = type.sizeOf(codeGen.ctx()) / elementSize;
        if (!count)
            return Result::Continue;

        MicroBuilder&  builder    = codeGen.builder();
        const MicroReg elementReg = codeGen.nextVirtualIntRegister();
        const MicroReg countReg   = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(elementReg, addressReg, MicroOpBits::B64);
        builder.emitLoadRegImm(countReg, ApInt(count, 64), MicroOpBits::B64);
        const MicroLabelRef loop = builder.createLabel();
        builder.placeLabel(loop);
        SWC_RESULT(emitElement(elementType, elementReg));
        builder.emitOpBinaryRegImm(elementReg, ApInt(elementSize, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loop);
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
