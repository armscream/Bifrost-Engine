// Engine/src/Core/service_registry.odin
package Core

import "core:log"
import "core:mem"

import hm "core:container/handle_map"

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
// Consumers access services through ServiceHandle rather than reaching
// directly into module implementations. The Service_Registry type is public
// because the SDK takes ^Service_Registry; the per-instance bookkeeping
// (Service_Instance) is internal.
// ============================================================================

@(private)
Service_Instance :: struct {
	handle:   ServiceHandle,
	owner:    ModuleHandle,
	name:     string,
	instance: rawptr,
	destroy:  proc(instance: rawptr),
	active:   bool,
}

Service_Registry :: struct {
	allocator:   mem.Allocator,
	slots:       hm.Dynamic_Handle_Map(Service_Instance, ServiceHandle),
	by_name:     map[string]ServiceHandle,
	initialized: bool,
}

// ============================================================================
// REGISTRY LIFECYCLE
// ============================================================================

@(private)
service_registry_init :: proc(registry: ^Service_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil do return false
	if registry.initialized {
		log.warn("Service registry is already initialized.")
		return false
	}
	registry.allocator = allocator
	hm.dynamic_init(&registry.slots, allocator)
	registry.by_name = make(map[string]ServiceHandle, allocator)
	registry.initialized = true
	log.info("Service registry initialized.")
	return true
}

@(private)
service_registry_destroy :: proc(registry: ^Service_Registry) {
	if registry == nil || !registry.initialized do return

	// Defensively destroy anything that remains — services should normally
	// already have been removed during module deactivation or unloading.
	it := hm.dynamic_iterator_make(&registry.slots)
	for service, _ in hm.iterate(&it) {
		if service.instance != nil && service.destroy != nil {
			service.destroy(service.instance)
		}
	}

	delete(registry.by_name)
	hm.dynamic_destroy(&registry.slots)
	registry.allocator = {}
	registry.initialized = false
}

// ============================================================================
// REGISTRY LOOKUP
// ============================================================================

@(private)
service_registry_get :: proc(
	registry: ^Service_Registry,
	handle: ServiceHandle,
) -> (
	^Service_Instance,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	if handle == INVALID_SERVICE_HANDLE do return nil, false
	service, ok := hm.get(&registry.slots, handle)
	if !ok do return nil, false
	if service.instance == nil do return nil, false
	return service, true
}

// ============================================================================
// REGISTRATION
// ============================================================================

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

	// Reject duplicate service names.
	if existing, found := registry.by_name[registration.name]; found {
		if _, valid := service_registry_get(registry, existing); valid {
			log.error(
				"Cannot register service '%s': service already registered [%d:%d].",
				registration.name,
				existing.idx,
				existing.gen,
			)
			return INVALID_SERVICE_HANDLE, false
		}
		// Stale by_name entry: drop it.
		delete_key(&registry.by_name, registration.name)
	}

	handle, alloc_err := hm.add(
		&registry.slots,
		Service_Instance{
			owner    = owner,
			name     = registration.name,
			instance = registration.instance,
			destroy  = registration.destroy,
			active   = true,
		},
	)
	if alloc_err != nil {
		log.error("Cannot register service '%s': allocator failure (%v).", registration.name, alloc_err)
		return INVALID_SERVICE_HANDLE, false
	}

	registry.by_name[registration.name] = handle
	log.info("Service registered: %s [%d:%d]", registration.name, handle.idx, handle.gen)

	return handle, true
}

@(private)
service_unregister :: proc(registry: ^Service_Registry, handle: ServiceHandle) -> bool {
	if registry == nil || !registry.initialized do return false
	service, ok := service_registry_get(registry, handle)
	if !ok do return false

	// Remove name lookup.
	if existing, found := registry.by_name[service.name]; found {
		if existing == handle {
			delete_key(&registry.by_name, service.name)
		}
	}

	// Destroy service-owned object.
	if service.instance != nil && service.destroy != nil do service.destroy(service.instance)

	// Remove from handle map (does not free the instance backing storage;
	// the map owns the slot).
	_, _ = hm.remove(&registry.slots, handle)
	return true
}

// service_unregister_all_owned drops every service owned by `owner`.
// Called during module unload so we don't leak service instances.
@(private)
service_unregister_all_owned :: proc(
	registry: ^Service_Registry,
	owner: ModuleHandle,
) -> int {
	if registry == nil || !registry.initialized do return 0

	count := 0
	it := hm.dynamic_iterator_make(&registry.slots)
	for service, h in hm.iterate(&it) {
		if service.owner != owner do continue
		if existing, found := registry.by_name[service.name]; found {
			if existing == h do delete_key(&registry.by_name, service.name)
		}
		if service.instance != nil && service.destroy != nil do service.destroy(service.instance)
		_, _ = hm.remove(&registry.slots, h)
		count += 1
	}
	return count
}