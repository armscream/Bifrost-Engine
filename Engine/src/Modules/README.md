## BF Engine Module Overview
This repository is part of the BF Engine ecosystem, a collection of modular libraries designed for game development. Each module provides a specific core functionality.

## Core Modules
**BF_ECS:** Entity-Component-System (ECS) framework. Provides the foundational architecture for organizing game objects and logic in a high-performance, data-oriented manner. https://github.com/armscream/BF_ECS
**BF_SDL3_GPU:** Graphics rendering module built on top of SDL3. Handles low-level GPU operations, window creation, and the rendering pipeline. https://github.com/armscream/BF_SDL3_GPU
**BF_Miniaudio:** Audio management module utilizing the Miniaudio library. Responsible for audio backend. https://github.com/armscream/BF_Miniaudio
**BF_Box3D_Physics:** 3D physics simulation module porting the Box3D library to Bifrost Engine. https://github.com/armscream/BF_Box3D_Physics
**BF_Renderer:** Vulkan and MoltenVK renderer module. https://github.com/armscream/BF_Renderer
**BF_Editor:** A planned visual editor tool for the BF Engine. Used for level design, asset management, and configuring game entities and components created with the ECS. https://github.com/armscream/BF_Editor
**BF_DAG:** Directed Acyclic Graph (DAG) execution system. Could be used for defining and executing complex, interdependent tasks, such as rendering passes, build pipelines, or complex gameplay events. https://github.com/armscream/BF_DAG

**How the Module API Works**
The BF Engine follows a modular API design. Each module exposes a well-defined Odin interface for its specific domain (e.g., ecs::World, graphics::Renderer, audio::Sound). Modules are typically initialized during engine startup and can interact with each other (e.g., the BF_Renderer might consume mesh data from the BF_ECS for drawing). This decoupled architecture allows developers to use individual components or swap them out for alternatives easily. For detailed API usage, please consult the documentation within each respective module's repository or see a future tutorial on how to create your own modules (Soon *TM).

## Module Installation
- All modules installed should be placed in the "src/Modules" directory, or in your Project's "modules" directory.
- The build system will automatically detect and compile them starting at your project's "modules" directory, if any duplicates are found, the project one found will be used.
- cd into your project directory and run `odin build ./rbs -out:rune.exe` - This builds the build system exe.
- from your project directory, run `./rune manifest` - this generates a manifest file for each module/ext/plugin (engine & project)
- from your project directory, run `./rune run DEBUG` - this builds your project in DEBUG mode, other modes include RELEASE, and EDITOR. The first run will generate a project.toml in your project directory's config folder, which the engine and build system needs.
- Edit your project.toml to configure your project's bootup parameters, this includes which modules, extensions and plugins to load.
- from your project directory, run `./rune run DEBUG` again and this will compile the correct libraries and run your project.

Build configurations will end up in the 'bin/' directory. bin/Debug, bin/Release, and bin/Editor.

Later versions will have build platform targets as well as seperating build and run. Currently, we only have a run command, which 
will destroy the .exe once the program exits.