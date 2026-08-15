YMIR ENGINE
rewrite v3?

How to build: 
cd into Project\rbs and run: odin build . -out:rune.exe  
this builds the rune.exe which you will need to build the engine and all modules.

run rune.exe with 
./rune run EDITOR - runs engine with "-vet -debug -define:RUN_EDITOR=true" and will also build the editor module
./rune run DEBUG - runs engine with "-vet -debug" - will not build the editor module
./rune run RELEASE - runs engine with "-vet -release" - will not build the editor module

Plans: 
Currently this only supports windows, I will later add support for linux and mac with .so and .dylib files and compilation targets.