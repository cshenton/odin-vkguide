package main

import "core:fmt"
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

create_engine :: proc() -> Engine {
	// Initialise window
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 0)
	window := glfw.CreateWindow(800, 600, "Vulkan Odin", nil, nil)

	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	// Create instance
	instance: vk.Instance
	extensions := glfw.GetRequiredInstanceExtensions()
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
			enabledExtensionCount = u32(len(extensions)),
			ppEnabledExtensionNames = &extensions[0],
		},
		nil,
		&instance,
	)
	if (result != .SUCCESS) {
		panic("pish")
	}

	vk.load_proc_addresses(instance)

	//

	// vk.load_proc_addresses(device)

	engine := Engine {
		window   = window,
		instance = instance,
	}
	return engine
}

destroy_engine :: proc(engine: ^Engine) {
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
