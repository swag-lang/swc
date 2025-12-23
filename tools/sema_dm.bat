@echo off
echo SYNTAX
call syntax_dm.bat %1 %2 %3 %4 %5 %6 %7 %8 %9
echo SEMA
swc_devmode sema --verify -d ../bin/tests/sema %1 %2 %3 %4 %5 %6 %7 %8 %9
