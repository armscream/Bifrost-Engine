# BIFROST ENGINE

![Bifrost Engine Logo](Engine\src\assets\Bifrost_Engine_Logo.png)

## An ECS based 3D Game Engine Written In Odin

## How to build

cd into Project and run: odin build ./rbs -out:rune.exe
this builds the rune.exe which you will need to build the engine and all modules.

### Run rune.exe with

- ./rune run EDITOR - runs engine with "-vet -debug -define:RUN_EDITOR=true" and will also build the editor module
- ./rune run DEBUG - runs engine with "-vet -debug" - will not build the editor module
- ./rune run RELEASE - runs engine with "-vet -release" - will not build the editor module
- ./rune manifest produces .toml manifest files for all components (modules/extensions/plugins)
- ./rune manifest --check exits 1 on a stale manifest
- This will build all dependencies listed in project.toml for the configuration you are running, as well as the executable into the bin directory. It also copies the assets, config, and scripts folders into the bin directory. It is recommended to only have .odin files directly under /Project.

## Plans

Currently this only supports windows, I will later add support for linux and mac with .so and .dylib files and platform-specific compilation targets.
Core Modules will provide all the features you would expect from a game engine, the benefit is that you will be able to swap out modules for other ones that provide the same services. Most Core modules will also be designed to be extensible, and hopefully this will allow for easy customization, and for the ability to run your project as lean as possible, or with a curated set of features.

## How the component system works

Engine will run with or without any components, however some components will be required for certain features. Core features like rendering, physics, audio, input, etc are singletons. You cannot load two renderer components at once.
List all components req'd in your project.toml, if you do not have one, run the engine once to generate one.
Anytime you update the engine, it is recommended to delete your project.toml file and run the engine again to generate an updated project.toml file. - Further info on components are in Engine/src/Modules/README.md.

- **Components:**
- Module = Core Engine capability/provider.
- Extension = Extends a Module, modules are responsible for providing extention points.
- Plugin = Project/Editor feature provider.
- SDK = the stable public interface they use to communicate with Ymir, as well as for the programmer.

### Engine intent

- PBR Renderer (main focus on the Bifrost_Renderer module, which will have Vulkan and MoltenVk backends)
- Directed Acrylic Graph (DAG) tasks and systems scheduler (ported)
- ECS - Entity Component System, will be a hybrid archetype system. (in development)
- Physics Engine - Probably Box3D
- Audio Engine - Probably mini-audio or just SDL3
- GUI Engine - Probably ImGui - Maybe a custom retained-mode GUI if i can hack it
- Replication - ECS component replication and some event and RPC replication for custom events.
I had this working in the old engine, add a replication component to an entity and it will replicate all dirty components set to replicate based off of individual protocols. Really handy system - reduces cognitive load significantly.
- Editor - IMGUI or custom RMGUI, not a priority.
- Networking - ENet is the best here, probably need a Steamworks component too.
- Chunk system - this ties into replication, physics, rendering, and any entity queries. Think 2d chunks or 3d for voxel worlds. This partitions the world, allows for asset streaming, and a lot of optimizations.
- AI/agent system - Not LLM, game AI. This would be a mix of GOAP and task-centred AI.

### V1 intent

- Every part of the engine intent here is at a shippable state. Editor can be bare-bones.
- Propper engine SDK, good module system, and a simple API that can actually make games.

## Creditation

Full credit for rune build system goes to the original author: 'dalapierre / David' - [https://github.com/dalapierre/rune.git](https://github.com/dalapierre/rune.git)

## AI Disclosure

AI has been used at times to generate some code, mostly in areas that the author had no interest in, such as much of the build system and the TOML serializer.
Other AI usage is mostly for documentation, and for planning, and asking questions about possible features, or how to implement some code. Everything else is written by the author.

## License

See the LICENSE file for the LSA (License Selection Agreement). Bifrost provides two options for licensing:

1. Commercial Engine License ("CEL")
2. Open Community Game License ("OCGL")

- **TLDR**: Commercial games can be freely made with Bifrost, but both licenses strictly restrict the monitization methods of the product in ways that are not anti-consumer. Ie: Box-cost, DLC and subscriptions are permitted, but **in-game monetization methods are strictly prohibited.**
- The OCGL is a license for open source projects. It allows you to use Bifrost in your open source projects, but you cannot monetize them outside of community donation sources. This is designed for protecting long-term open-source projects.

## Contributing

Contributions are welcome! If you'd like to contribute to the Bifrost Engine, please read this first:

1. For small targeted fixes, feel free to open a pull request.
2. For larger changes, please open an issue first to discuss the change.
3. If you would like to add a feature, feel free to create a Component (module/extension/plugin) first, share it, and let others know. It's a great way to get feedback and ideas and to test whether or not this should be implemented in the core engine or as a core component.

- Features need to be unit tested, regressions to current implementations will not be accepted unless the added feature justifies the change.
- Pull requests should be human reviewed prior to submission. Completely AI generated PRs will be denied. - This isnt to say that I am against AI usage, but that every line of code should be reviewed by a human.
