@echo off
swc_devmode syntax --no-verify -d ../bin/tests/lexer %1 %2 %3 %4 %5 %6 %7 %8 %9
swc_devmode syntax --verify -d ../bin/tests/parser %1 %2 %3 %4 %5 %6 %7 %8 %9
swc_devmode build -m ../bin/tests/legit %1 %2 %3 %4 %5 %6 %7 %8 %9
