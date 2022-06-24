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
	graphics_queue:  vk.Queue,
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

	// Create surface
	surface: vk.SurfaceKHR
	result = glfw.CreateWindowSurface(instance, window, nil, &surface)
	if (result != .SUCCESS) {
		panic("surface creation failed")
	}

	// Query physical devices
	device_count: u32
	gpu: vk.PhysicalDevice
	best_score := 0
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, &devices[0])
	for dev in devices {
		score := 0

		device_features: vk.PhysicalDeviceFeatures
		device_properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceFeatures(dev, &device_features)
		vk.GetPhysicalDeviceProperties(dev, &device_properties)

		if device_properties.deviceType == .DISCRETE_GPU {
			score += 1000
		}

		if score > best_score {
			gpu = dev
			best_score = score
		}
	}

	// Find queue families
	// TODO: Actually this should be used to choose the device
	graphics_index: u32
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &queue_family_count, nil)
	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &queue_family_count, &queue_families[0])
	for family, i in queue_families {
		is_present: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(gpu, u32(i), surface, &is_present)
		if .GRAPHICS in family.queueFlags && is_present {
			graphics_index = u32(i)
		}
	}

	// Create logical device
	device: vk.Device
	queue_priority := f32(1)
	queue_create_info := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = graphics_index,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}
	device_create_info := vk.DeviceCreateInfo {
		sType                = .DEVICE_CREATE_INFO,
		pQueueCreateInfos    = &queue_create_info,
		queueCreateInfoCount = 1,
		pEnabledFeatures     = &vk.PhysicalDeviceFeatures{},
		enabledLayerCount    = len(validation_layers),
		ppEnabledLayerNames  = &validation_layers[0],
	}
	result = vk.CreateDevice(gpu, &device_create_info, nil, &device)
	if (result != .SUCCESS) {
		panic("device creation failed")
	}

	// Get Queues
	graphics_queue: vk.Queue
	vk.GetDeviceQueue(device, graphics_index, 0, &graphics_queue)

	// Load device procedures
	vk.load_proc_addresses(device)

	engine := Engine {
		window          = window,
		instance        = instance,
		debug_messenger = debug_messenger,
		gpu             = gpu,
		device          = device,
		graphics_queue  = graphics_queue,
		surface         = surface,
	}
	return engine
}

destroy_engine :: proc(engine: ^Engine) {
	vk.DestroyDevice(engine.device, nil)
	vk.DestroySurfaceKHR(engine.instance, engine.surface, nil)
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
