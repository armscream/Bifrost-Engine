// Engine/src/Core/event_registry.odin
package Core

import "core:log"
import "core:mem"

import hm "core:container/handle_map"

// ============================================================================
// EVENT REGISTRY
// ============================================================================
//
// Events are described by Event_Registration (name + payload size +
// alignment). The event *bus* (dispatch) is owned by a future module;
// this registry only tracks event-type metadata so consumers can look up
// `EventHandle` by name and resolve payload layout.
//
// Same handle-map pattern as Service_Registry / Resource_Registry.
// ============================================================================

@(private)
Event_Info :: struct {
	handle:     EventHandle,
	owner:      ModuleHandle,
	name:       string,
	size:       u32,
	allignment: u32,
}

Event_Registry :: struct {
	allocator:   mem.Allocator,
	slots:       hm.Dynamic_Handle_Map(Event_Info, EventHandle),
	by_name:     map[string]EventHandle,
	initialized: bool,
}

@(private)
event_registry_init :: proc(registry: ^Event_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil do return false
	if registry.initialized {
		log.warn("Event registry already initialized.")
		return false
	}
	registry.allocator = allocator
	hm.dynamic_init(&registry.slots, allocator)
	registry.by_name = make(map[string]EventHandle, allocator)
	registry.initialized = true
	log.info("Event registry initialized.")
	return true
}

@(private)
event_registry_destroy :: proc(registry: ^Event_Registry) {
	if registry == nil || !registry.initialized do return

	delete(registry.by_name)
	hm.dynamic_destroy(&registry.slots)
	registry.allocator = {}
	registry.initialized = false
}

@(private)
event_registry_get :: proc(
	registry: ^Event_Registry,
	handle: EventHandle,
) -> (
	^Event_Info,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	if handle == INVALID_EVENT_HANDLE do return nil, false
	info, ok := hm.get(&registry.slots, handle)
	if !ok do return nil, false
	return info, true
}

@(private)
event_register :: proc(
	registry: ^Event_Registry,
	owner: ModuleHandle,
	registration: Event_Registration,
) -> (
	EventHandle,
	bool,
) {
	if registry == nil || !registry.initialized do return INVALID_EVENT_HANDLE, false
	if len(registration.name) == 0 {
		log.error("Cannot register event: event has no name.")
		return INVALID_EVENT_HANDLE, false
	}
	if registration.size == 0 {
		log.error("Cannot register event '%s': size is 0.", registration.name)
		return INVALID_EVENT_HANDLE, false
	}

	if existing, found := registry.by_name[registration.name]; found {
		if _, valid := event_registry_get(registry, existing); valid {
			log.error(
				"Cannot register event '%s': event already registered [%d:%d].",
				registration.name,
				existing.idx,
				existing.gen,
			)
			return INVALID_EVENT_HANDLE, false
		}
		delete_key(&registry.by_name, registration.name)
	}

	handle, alloc_err := hm.add(
		&registry.slots,
		Event_Info{
			owner      = owner,
			name       = registration.name,
			size       = registration.size,
			allignment = registration.allignment,
		},
	)
	if alloc_err != nil {
		log.error("Cannot register event '%s': allocator failure (%v).", registration.name, alloc_err)
		return INVALID_EVENT_HANDLE, false
	}

	registry.by_name[registration.name] = handle
	log.info("Event registered: %s [%d:%d]", registration.name, handle.idx, handle.gen)

	return handle, true
}

// event_unregister_all_owned drops every event owned by `owner`.
@(private)
event_unregister_all_owned :: proc(
	registry: ^Event_Registry,
	owner: ModuleHandle,
) -> int {
	if registry == nil || !registry.initialized do return 0

	count := 0
	it := hm.dynamic_iterator_make(&registry.slots)
	for info, h in hm.iterate(&it) {
		if info.owner != owner do continue
		if existing, found := registry.by_name[info.name]; found {
			if existing == h do delete_key(&registry.by_name, info.name)
		}
		_, _ = hm.remove(&registry.slots, h)
		count += 1
	}
	return count
}
