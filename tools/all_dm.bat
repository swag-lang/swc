@echo off

call syntax_dm.bat %1 %2 %3 %4 %5 %6 %7 %8 %9

call sema_dm.bat --backend-optimize O0 %1 %2 %3 %4 %5 %6 %7 %8 %9
call sema_dm.bat --backend-optimize O1 %1 %2 %3 %4 %5 %6 %7 %8 %9
call sema_dm.bat --backend-optimize O2 %1 %2 %3 %4 %5 %6 %7 %8 %9
call sema_dm.bat --backend-optimize Os %1 %2 %3 %4 %5 %6 %7 %8 %9
call sema_dm.bat --backend-optimize Oz %1 %2 %3 %4 %5 %6 %7 %8 %9
