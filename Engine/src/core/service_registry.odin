// Engine/src/Core/service_registry.odin
package Core

import "core:log"
import "core:mem"

// ============================================================================
// SERVICE REGISTRY
// ============================================================================
//
// Services are long-lived interfaces exposed by modules.
//
// Example:
//
//     DAG module -> Scheduler service
//
// Consumers should access services through ServiceHandle rather than
// reaching directly into module implementations.
//
// ============================================================================

Service_Instance :: struct {
	handle:   ServiceHandle,
	owner:    ModuleHandle,
	name:     string,
	instance: rawptr,
	destroy:  proc(instance: rawptr),
	active:   bool,
}

Service_Registry :: struct {
	allocator:    mem.Allocator,
	services:     [dynamic]Service_Instance,
	generations:  [dynamic]u32,
	free_indices: [dynamic]u32,
	by_name:      map[string]ServiceHandle,
	initialized:  bool,
}

//  Service_Registry init
@(private)
service_registry_init :: proc(registry: ^Service_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil do return false
	if registry.initialized {
		log.warn("Service registry is already initialized.")
		return false
	}
	registry.allocator = allocator

	// Slot zero is permanently invalid.
	registry.services = make([dynamic]Service_Instance, 1, allocator)
	append(&registry.services, Service_Instance{})

	registry.generations = make([dynamic]u32, 1, allocator)
	append(&registry.generations, SERVICE_GENERATION_INVALID)

	registry.by_name = make(map[string]ServiceHandle, allocator)

	registry.initialized = true

	log.info("Service registry initialized.")
	return true
}

// Service_Registry destroy
@(private)
service_registry_destroy :: proc(registry: ^Service_Registry) {
	if registry == nil || !registry.initialized do return

	// Services should normally already have been removed during module
	// deactivation or unloading.
	// so we defensively destroy anything that remains.
	for i := 1; i < len(registry.services); i += 1 {
		service := &registry.services[i]
		if service.instance != nil && service.destroy != nil do service.destroy(service.instance)
	}

	delete(registry.by_name)
	delete(registry.free_indices)
	delete(registry.generations)
	delete(registry.services)

	registry.allocator = {}
	registry.initialized = false
}

// Validate service handle
@(private)
service_registry_get :: proc(
	registry: ^Service_Registry,
	handle: ServiceHandle,
) -> (
	^Service_Instance,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	if handle.index == SERVICE_INDEX_INVALID do return nil, false
	if handle.index >= u32(len(registry.services)) do return nil, false
	if handle.generation == SERVICE_GENERATION_INVALID || handle.generation != registry.generations[handle.index] do return nil, false

	service := &registry.services[handle.index]
	if service.handle.index != handle.index do return nil, false
	if service.handle.generation != handle.generation do return nil, false
	if service.instance == nil do return nil, false

	return service, true
}

// Register service
@(private)
service_register :: proc(
	registry: ^Service_Registry,
	owner: ModuleHandle,
	registration: Service_Registration,
) -> (
	ServiceHandle,
	bool,
) {
	if registry == nil || !registry.initialized do return INVALID_SERVICE_HANDLE, false
	if len(registration.name) == 0 {
		log.error("Cannot register service: service has no name.")
		return INVALID_SERVICE_HANDLE, false
	}
	if registration.instance == nil {
		log.error("Cannot register service '%s': instance is nil.", registration.name)
		return INVALID_SERVICE_HANDLE, false
	}

	// reject duplication service names.
	if existing, found := registry.by_name[registration.name]; found {
		log.error(
			"Cannot register service '%s': service already registered [%d:%d].",
			registration.name,
			existing.index,
			existing.generation,
		)
		return INVALID_SERVICE_HANDLE, false
	}

    // Allocate slot.
	index: u32
	if len(registry.free_indices) > 0 {
		index = pop(&registry.free_indices)
	} else {
		index = u32(len(registry.services))
		append(&registry.services, Service_Instance{})
		append(&registry.generations, SERVICE_GENERATION_INVALID)
	}

	// Advance generation.
	generation := registry.generations[index]
	if generation == SERVICE_GENERATION_INVALID {
		generation = 1
	} else {
		generation += 1
		if generation == SERVICE_GENERATION_INVALID {
			generation = 1
		}
	}
	registry.generations[index] = generation
	handle := ServiceHandle {
		index      = index,
		generation = generation,
	}

	// Create service instance.
	service := Service_Instance {
		handle   = handle,
		owner    = owner,
		name     = registration.name,
		instance = registration.instance,
		destroy  = registration.destroy,
		active   = true,
	}
	registry.services[index] = service
	registry.by_name[service.name] = handle
	log.info("Service registered: %s [%d:%d]", service.name, handle.index, handle.generation)

	return handle, true
}

// Remove Service.
service_unregister :: proc(registry: ^Service_Registry, handle: ServiceHandle) -> bool {
	if registry == nil || !registry.initialized do return false
	service, ok := service_registry_get(registry, handle)
	if !ok do return false

	// remove name lookup.
	if existing, found := registry.by_name[service.name]; found {
		if existing == handle {
			delete_key(&registry.by_name, service.name)
		}
	}

	// destroy service-owned object.
	if service.instance != nil && service.destroy != nil do service.destroy(service.instance)

	// clear slot.
	registry.services[handle.index] = Service_Instance{}
	// Generation is deliberately preserved.
	append(&registry.free_indices, handle.index)
	return true
}