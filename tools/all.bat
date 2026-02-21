@echo off

call syntax.bat %1 %2 %3 %4 %5 %6 %7 %8 %9

call sema.bat --backend-optimize O0 %1 %2 %3 %4 %5 %6 %7 %8 %9
call sema.bat --backend-optimize O1 %1 %2 %3 %4 %5 %6 %7 %8 %9
call sema.bat --backend-optimize O2 %1 %2 %3 %4 %5 %6 %7 %8 %9
call sema.bat --backend-optimize Os %1 %2 %3 %4 %5 %6 %7 %8 %9
call sema.bat --backend-optimize Oz %1 %2 %3 %4 %5 %6 %7 %8 %9
