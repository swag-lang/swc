; MSVC x64 Release, ConstantManager::get; direct-page path ends at the first ret.
; The large-block fallback follows it and is not changed by the page-table optimization.

; control, source 3965e1b51: 31 non-nop instructions on the direct-page path.
?get@ConstantManager@swc@@QEBAAEBVConstantValue@2@V?$StrongRef@VConstantValue@swc@@@2@@Z (public: class swc::ConstantValue const & __cdecl swc::ConstantManager::get(class swc::StrongRef<class swc::ConstantValue>)const ):
  0000000000000000: mov         qword ptr [rsp+10h],rbx
  0000000000000005: push        rsi
  0000000000000006: sub         rsp,20h
  000000000000000A: mov         ebx,edx
  000000000000000C: mov         esi,edx
  000000000000000E: shr         rbx,1Ch
  0000000000000012: and         esi,0FFFFFFFh
  0000000000000018: shl         rbx,0Ch
  000000000000001C: add         rbx,rcx
  000000000000001F: movzx       eax,byte ptr [rbx+180h]
  0000000000000026: nop
  0000000000000027: test        al,al
  0000000000000029: jne         000000000000006D
  000000000000002B: mov         r9,qword ptr [rbx+48h]
  000000000000002F: mov         ecx,dword ptr [rbx+64h]
  0000000000000032: mov         r8d,dword ptr [rbx+68h]
  0000000000000036: nop
  0000000000000037: mov         eax,esi
  0000000000000039: shrx        rcx,rax,rcx
  000000000000003E: mov         rax,qword ptr [r9]
  0000000000000041: lea         rdx,[rcx*8]
  0000000000000049: mov         rcx,qword ptr [rax+rcx*8]
  000000000000004D: mov         eax,dword ptr [rcx+8]
  0000000000000050: mov         ecx,esi
  0000000000000052: mov         eax,r8d
  0000000000000055: and         rax,rcx
  0000000000000058: mov         rcx,qword ptr [r9]
  000000000000005B: mov         rdx,qword ptr [rdx+rcx]
  000000000000005F: add         rax,qword ptr [rdx]
  0000000000000062: mov         rbx,qword ptr [rsp+38h]
  0000000000000067: add         rsp,20h
  000000000000006B: pop         rsi
  000000000000006C: ret
  000000000000006D: mov         qword ptr [rsp+30h],rdi
  0000000000000072: lea         rdi,[rbx+188h]
  0000000000000079: mov         rcx,rdi
  000000000000007C: call        _Smtx_lock_shared
  0000000000000081: mov         r8d,30h
  0000000000000087: mov         edx,esi
  0000000000000089: mov         rcx,rbx
  000000000000008C: call        ?findPtrLocked@DataSegment@swc@@AEBAPEBW4byte@std@@II@Z
  0000000000000091: mov         rcx,rdi
  0000000000000094: mov         rbx,rax
  0000000000000097: call        _Smtx_unlock_shared
  000000000000009C: mov         rdi,qword ptr [rsp+30h]
  00000000000000A1: mov         rax,rbx
  00000000000000A4: mov         rbx,qword ptr [rsp+38h]
  00000000000000A9: add         rsp,20h
  00000000000000AD: pop         rsi
  00000000000000AE: ret

; pages, source ecb64e0f2e: 26 non-nop instructions on the direct-page path.
?get@ConstantManager@swc@@QEBAAEBVConstantValue@2@V?$StrongRef@VConstantValue@swc@@@2@@Z (public: class swc::ConstantValue const & __cdecl swc::ConstantManager::get(class swc::StrongRef<class swc::ConstantValue>)const ):
  0000000000000000: mov         qword ptr [rsp+10h],rbx
  0000000000000005: push        rsi
  0000000000000006: sub         rsp,20h
  000000000000000A: mov         ebx,edx
  000000000000000C: mov         esi,edx
  000000000000000E: shr         rbx,1Ch
  0000000000000012: and         esi,0FFFFFFFh
  0000000000000018: shl         rbx,0Ch
  000000000000001C: add         rbx,rcx
  000000000000001F: movzx       eax,byte ptr [rbx+180h]
  0000000000000026: nop
  0000000000000027: test        al,al
  0000000000000029: jne         0000000000000058
  000000000000002B: mov         r9,qword ptr [rbx+48h]
  000000000000002F: mov         edx,dword ptr [rbx+64h]
  0000000000000032: mov         eax,dword ptr [rbx+68h]
  0000000000000035: nop
  0000000000000036: mov         ecx,esi
  0000000000000038: and         eax,esi
  000000000000003A: shrx        r8,rcx,rdx
  000000000000003F: mov         rcx,qword ptr [r9]
  0000000000000042: mov         rdx,qword ptr [rcx+r8*8]
  0000000000000046: nop
  0000000000000047: mov         ecx,dword ptr [rdx+8]
  000000000000004A: add         rax,qword ptr [rdx]
  000000000000004D: mov         rbx,qword ptr [rsp+38h]
  0000000000000052: add         rsp,20h
  0000000000000056: pop         rsi
  0000000000000057: ret
  0000000000000058: mov         qword ptr [rsp+30h],rdi
  000000000000005D: lea         rdi,[rbx+188h]
  0000000000000064: mov         rcx,rdi
  0000000000000067: call        _Smtx_lock_shared
  000000000000006C: mov         r8d,30h
  0000000000000072: mov         edx,esi
  0000000000000074: mov         rcx,rbx
  0000000000000077: call        ?findPtrLocked@DataSegment@swc@@AEBAPEBW4byte@std@@II@Z
  000000000000007C: mov         rcx,rdi
  000000000000007F: mov         rbx,rax
  0000000000000082: call        _Smtx_unlock_shared
  0000000000000087: mov         rdi,qword ptr [rsp+30h]
  000000000000008C: mov         rax,rbx
  000000000000008F: mov         rbx,qword ptr [rsp+38h]
  0000000000000094: add         rsp,20h
  0000000000000098: pop         rsi
  0000000000000099: ret
