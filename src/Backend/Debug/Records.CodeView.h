#pragma once

SWC_BEGIN_NAMESPACE();

// CodeView constants shared by the object writer, section merger, and PDB builder.
namespace CodeViewRecords
{
    constexpr uint32_t K_CV_SIGNATURE_C13  = 4;
    constexpr uint32_t K_CV_TYPE_SIGNATURE = 4;

    constexpr uint32_t K_DEBUG_S_SYMBOLS     = 0xF1;
    constexpr uint32_t K_DEBUG_S_LINES       = 0xF2;
    constexpr uint32_t K_DEBUG_S_STRINGTABLE = 0xF3;
    constexpr uint32_t K_DEBUG_S_FILECHKSMS  = 0xF4;

    constexpr uint16_t K_S_END         = 0x0006;
    constexpr uint16_t K_S_FRAMEPROC   = 0x1012;
    constexpr uint16_t K_S_OBJNAME     = 0x1101;
    constexpr uint16_t K_S_COMPILE3    = 0x113C;
    constexpr uint16_t K_S_UDT         = 0x1108;
    constexpr uint16_t K_S_LDATA32     = 0x110C;
    constexpr uint16_t K_S_GDATA32     = 0x110D;
    constexpr uint16_t K_S_REGREL32    = 0x1111;
    constexpr uint16_t K_S_GPROC32_ID  = 0x1147;
    constexpr uint16_t K_S_BUILDINFO   = 0x114C;
    constexpr uint16_t K_S_PROC_ID_END = 0x114F;

    constexpr uint16_t K_LF_MODIFIER  = 0x1001;
    constexpr uint16_t K_LF_POINTER   = 0x1002;
    constexpr uint16_t K_LF_PROCEDURE = 0x1008;
    constexpr uint16_t K_LF_ARGLIST   = 0x1201;
    constexpr uint16_t K_LF_FIELDLIST = 0x1203;
    constexpr uint16_t K_LF_INDEX     = 0x1404;
    constexpr uint16_t K_LF_ARRAY     = 0x1503;
    constexpr uint16_t K_LF_STRUCTURE = 0x1505;
    constexpr uint16_t K_LF_MEMBER    = 0x150D;
    constexpr uint16_t K_LF_FUNC_ID   = 0x1601;
    constexpr uint16_t K_LF_BUILDINFO = 0x1603;
    constexpr uint16_t K_LF_STRING_ID = 0x1605;

    constexpr uint16_t K_CV_CFL_AMD64 = 0x00D0;
    constexpr uint32_t K_CV_CFL_CXX   = 0x01; // S_COMPILE3 language byte: C++.
}

SWC_END_NAMESPACE();
