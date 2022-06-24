package main

import "core:fmt"
import "core:runtime"
import vk "vendor:vulkan"
import "vendor:glfw"

Engine :: struct {
	window:          glfw.WindowHandle,
	instance:        vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,
	gpu:             vk.PhysicalDevice,
	device:          vk.Device,
	surface:         vk.SurfaceKHR,
}

debug_callback :: proc "c" (
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_type: vk.DebugUtilsMessageTypeFlagsEXT,
	p_callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
) -> u32 {
	context = runtime.default_context()
	fmt.printf("validation layer: %s\n", p_callback_data.pMessage)
	return 0
}

create_engine :: proc() -> Engine {
	// Initialise window
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 0)
	window := glfw.CreateWindow(800, 600, "Vulkan Odin", nil, nil)

	// Load base procedures
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	// Check for validation layers
	validation_layers := [1]cstring{"VK_LAYER_KHRONOS_validation"}
	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	layers := make([]vk.LayerProperties, layer_count)
	defer delete(layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, &layers[0])
	for valid_layer in validation_layers {
		layer_found := false
		for layer in &layers {
			if string(valid_layer) == string(cstring(&layer.layerName[0])) {
				layer_found = true
			}
		}

		if !layer_found {
			panic("validation layer not found")
		}
	}

	// Get required extensions
	instance: vk.Instance
	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	all_extensions := make([]cstring, len(glfw_extensions) + 1)
	defer delete(all_extensions)
	all_extensions[0] = vk.EXT_DEBUG_UTILS_EXTENSION_NAME
	for ext, i in glfw_extensions {
		all_extensions[i + 1] = ext
	}

	// TODO: Check for required extensions
	extension_count: u32
	vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
	extensions := make([]vk.ExtensionProperties, extension_count)
	defer delete(extensions)
	vk.EnumerateInstanceExtensionProperties(nil, &extension_count, &extensions[0])
	fmt.println("available extensions")
	for ext in extensions {
		fmt.printf("\t%s\n", ext.extensionName)
	}

	// Create instance
	result := vk.CreateInstance(
		&vk.InstanceCreateInfo{
			sType = .INSTANCE_CREATE_INFO,
			pApplicationInfo = &vk.ApplicationInfo{
				sType = .APPLICATION_INFO,
				pApplicationName = "Vulkan Odin",
				applicationVersion = vk.MAKE_VERSION(1, 0, 0),
				pEngineName = "Odin",
				engineVersion = vk.MAKE_VERSION(1, 0, 0),
				apiVersion = vk.API_VERSION_1_3,
			},
			enabledExtensionCount = u32(len(all_extensions)),
			ppEnabledExtensionNames = &all_extensions[0],
			enabledLayerCount = 1,
			ppEnabledLayerNames = &validation_layers[0],
		},
		nil,
		&instance,
	)
	if (result != .SUCCESS) {
		panic("pish")
	}

	// Load instance procedures
	vk.load_proc_addresses(instance)

	// Create debug messenger
	debug_messenger: vk.DebugUtilsMessengerEXT
	debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
		sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {.ERROR, .INFO, .VERBOSE, .WARNING},
		messageType = {.GENERAL, .PERFORMANCE, .VALIDATION},
		pfnUserCallback = vk.ProcDebugUtilsMessengerCallbackEXT(debug_callback),
		pUserData = nil,
	}
	result = vk.CreateDebugUtilsMessengerEXT(
		instance,
		&debug_create_info,
		nil,
		&debug_messenger,
	)
	if (result != .SUCCESS) {
		panic("pish")
	}

	// Load device procedures
	// vk.load_proc_addresses(device)

	engine := Engine {
		window          = window,
		instance        = instance,
		debug_messenger = debug_messenger,
	}
	return engine
}

destroy_engine :: proc(engine: ^Engine) {
	vk.DestroyDebugUtilsMessengerEXT(engine.instance, engine.debug_messenger, nil)
	vk.DestroyInstance(engine.instance, nil)
	glfw.DestroyWindow(engine.window)
	glfw.Terminate()
}

main :: proc() {
	engine := create_engine()
	defer destroy_engine(&engine)

	for !glfw.WindowShouldClose(engine.window) {
		glfw.PollEvents()
	}
}
