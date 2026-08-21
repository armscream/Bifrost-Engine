BIFROST ENGINE

![Bifrost Engine Logo](Engine\src\assets\Bifrost_Engine_Logo.png)   

How to build: 
cd into Project and run: odin build ./rbs -out:rune.exe 
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

Module = Engine capability/provider.
Plugin = Project/Editor extension.
SDK = the stable public interface they use to communicate with Ymir, as well as for the programmer.

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
- Chunk system - this ties into replication, physics, rendering, and any entity queries. Think 2d chunks or 3d for voxel worlds. This partitions the world, allows for asset streaming, and a lot of optimizations.
- AI/agent system - Not LLM, game AI. This would be a mix of GOAP and task-centred AI. 

V1 intent:
- Every part of the engine intent here is at a shippable state. Editor can be bare-bones.
- Propper engine SDK, good module system, and a simple API that can actually make games.