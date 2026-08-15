YMIR ENGINE
rewrite v3?

![Ymir Engine Logo](Engine\src\assets\Ymir_Engine_Logo.png)   

How to build: 
cd into Project\rbs and run: odin build . -out:rune.exe  
this builds the rune.exe which you will need to build the engine and all modules.

Run rune.exe with 
./rune run EDITOR - runs engine with "-vet -debug -define:RUN_EDITOR=true" and will also build the editor module
./rune run DEBUG - runs engine with "-vet -debug" - will not build the editor module
./rune run RELEASE - runs engine with "-vet -release" - will not build the editor module
This will build all dependencies listed in project.json for the configuration you are running, as well as the executable into the bin directory. It also copies the assets, config, and scripts folders into the bin directory. It is recommended to only have .odin files directly under /Project.

Plans: 
Currently this only supports windows, I will later add support for linux and mac with .so and .dylib files and compilation targets.

How the module system works: 
Engine will run with or without any modules, however some modules will be required for certain features. Core features like rendering, physics, audio, input, etc are singletons. You cannot load two renderer modules at once.
List all modules req'd in your project.json, if you do not have one, run the engine once to generate one.
Anytime you update the engine, it is recommended to delete your project.json file and run the engine again to generate an updated project.json file.

Modules must follow a simple API, exporting what is listed in module_interface.odin - which can/will change version-to-version.
// Standard module entry points that every .dll must export
Module_Load    :: proc() -> bool
Module_Unload :: proc()
Module_Update  :: proc(dt: f32)
Module_Render  :: proc() // Optional, for renderers   

Modules can be loaded dynamically at runtime, and unloaded when they are no longer needed. Typically they will load on engine_init and unload on engine_shutdown.

Plugins are currently the same as modules, but will be different in the future.

Engine intent: 
- PBR Renderer (main focus on the Bifrost_Renderer module, which will have Vulkan and MoltenVk backends)
- Directed Acrylic Graph (DAG) tasks and systems scheduler (already developed, needs to be ported)
- ECS - Entity Component System, will be non-archetypical
- Physics Engine - Probably Box3D
- Audio Engine - Probably mini-audio or just SDL3
- GUI Engine - Probably ImGui - Maybe a custom retained-mode GUI if i can hack it
- Replication - ECS component replication and some event and RPC replication for custom events. 
I had this working in the old engine, add a replication component to an entity and it will replicate all dirty components set to replicate based off of individual protocols. Really handy system - reduces cognitive load significantly.
- Editor - IMGUI or custom RMGUI, not a priority.
- Networking - ENet is the best here, probably need a Steamworks component too.

V1 intent:
- Every part of the engine intent here is at a shippable state. Editor can be bare-bones.
- Propper engine SDK, good module system, and a simple API that can actually make games.