// Engine/src/Core/resource_registry.odin
package Core

import "core:log"
import "core:mem"

import hm "core:container/handle_map"

// ============================================================================
// RESOURCE REGISTRY
// ============================================================================
//
// Resources are named runtime objects owned by a module/extension/plugin.
// Mirrors Service_Registry — the same handle-map pattern, the same
// `by_name` lookup, the same `destroy` callback ownership rules.
//
// Consumers reach resources through ResourceHandle and the SDK
// (`service_find`-style lookup helpers), never through the owning module
// directly.
// ============================================================================

@(private)
Resource_Instance :: struct {
	handle:   ResourceHandle,
	owner:    ModuleHandle,
	name:     string,
	instance: rawptr,
	destroy:  proc(instance: rawptr),
}

Resource_Registry :: struct {
	allocator:   mem.Allocator,
	slots:       hm.Dynamic_Handle_Map(Resource_Instance, ResourceHandle),
	by_name:     map[string]ResourceHandle,
	initialized: bool,
}

@(private)
resource_registry_init :: proc(registry: ^Resource_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil do return false
	if registry.initialized {
		log.warn("Resource registry already initialized.")
		return false
	}
	registry.allocator = allocator
	hm.dynamic_init(&registry.slots, allocator)
	registry.by_name = make(map[string]ResourceHandle, allocator)
	registry.initialized = true
	log.info("Resource registry initialized.")
	return true
}

@(private)
resource_registry_destroy :: proc(registry: ^Resource_Registry) {
	if registry == nil || !registry.initialized do return

	// Defensively destroy anything that remains.
	it := hm.dynamic_iterator_make(&registry.slots)
	for resource, _ in hm.iterate(&it) {
		if resource.instance != nil && resource.destroy != nil {
			resource.destroy(resource.instance)
		}
	}

	delete(registry.by_name)
	hm.dynamic_destroy(&registry.slots)
	registry.allocator = {}
	registry.initialized = false
}

@(private)
resource_registry_get :: proc(
	registry: ^Resource_Registry,
	handle: ResourceHandle,
) -> (
	^Resource_Instance,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	if handle == INVALID_RESOURCE_HANDLE do return nil, false
	resource, ok := hm.get(&registry.slots, handle)
	if !ok do return nil, false
	if resource.instance == nil do return nil, false
	return resource, true
}

@(private)
resource_register :: proc(
	registry: ^Resource_Registry,
	owner: ModuleHandle,
	registration: Resource_Registration,
) -> (
	ResourceHandle,
	bool,
) {
	if registry == nil || !registry.initialized do return INVALID_RESOURCE_HANDLE, false
	if len(registration.name) == 0 {
		log.error("Cannot register resource: resource has no name.")
		return INVALID_RESOURCE_HANDLE, false
	}
	if registration.instance == nil {
		log.error("Cannot register resource '%s': instance is nil.", registration.name)
		return INVALID_RESOURCE_HANDLE, false
	}

	if existing, found := registry.by_name[registration.name]; found {
		if _, valid := resource_registry_get(registry, existing); valid {
			log.error(
				"Cannot register resource '%s': resource already registered [%d:%d].",
				registration.name,
				existing.idx,
				existing.gen,
			)
			return INVALID_RESOURCE_HANDLE, false
		}
		delete_key(&registry.by_name, registration.name)
	}

	handle, alloc_err := hm.add(
		&registry.slots,
		Resource_Instance{
			owner    = owner,
			name     = registration.name,
			instance = registration.instance,
			destroy  = registration.destroy,
		},
	)
	if alloc_err != nil {
		log.error("Cannot register resource '%s': allocator failure (%v).", registration.name, alloc_err)
		return INVALID_RESOURCE_HANDLE, false
	}

	registry.by_name[registration.name] = handle
	log.info("Resource registered: %s [%d:%d]", registration.name, handle.idx, handle.gen)

	return handle, true
}

@(private)
resource_unregister :: proc(registry: ^Resource_Registry, handle: ResourceHandle) -> bool {
	if registry == nil || !registry.initialized do return false
	resource, ok := resource_registry_get(registry, handle)
	if !ok do return false

	if existing, found := registry.by_name[resource.name]; found {
		if existing == handle {
			delete_key(&registry.by_name, resource.name)
		}
	}

	if resource.instance != nil && resource.destroy != nil do resource.destroy(resource.instance)

	_, _ = hm.remove(&registry.slots, handle)
	return true
}

// resource_unregister_all_owned drops every resource owned by `owner`.
// Called when a module is deactivated/unloaded so we don't leak.
@(private)
resource_unregister_all_owned :: proc(
	registry: ^Resource_Registry,
	owner: ModuleHandle,
) -> int {
	if registry == nil || !registry.initialized do return 0

	count := 0
	it := hm.dynamic_iterator_make(&registry.slots)
	for resource, h in hm.iterate(&it) {
		if resource.owner != owner do continue
		if existing, found := registry.by_name[resource.name]; found {
			if existing == h do delete_key(&registry.by_name, resource.name)
		}
		if resource.instance != nil && resource.destroy != nil do resource.destroy(resource.instance)
		_, _ = hm.remove(&registry.slots, h)
		count += 1
	}
	return count
}
