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
	result :=
		vk.CreateInstance(
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
		panic("Failed to create instance")
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
	result = vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &debug_messenger)
	if (result != .SUCCESS) {
		panic("Failed to create debug messenger")
	}

	// Create surface
	surface: vk.SurfaceKHR
	result = glfw.CreateWindowSurface(instance, window, nil, &surface)
	if (result != .SUCCESS) {
		panic("Failed to create surface")
	}

	// Find an appropriate physical device
	gpu: vk.PhysicalDevice
	graphics_index: u32
	gpu_found := false

	device_count: u32
	vk.EnumeratePhysicalDevices(instance, &device_count, nil)
	devices := make([]vk.PhysicalDevice, device_count)
	defer delete(devices)
	vk.EnumeratePhysicalDevices(instance, &device_count, &devices[0])

	for dev in devices {
		// Ensure the device has the swapchain extension
		has_extension := false
		dev_extension_count: u32
		vk.EnumerateDeviceExtensionProperties(dev, nil, &dev_extension_count, nil)
		dev_extensions := make([]vk.ExtensionProperties, dev_extension_count)
		defer delete(dev_extensions)
		vk.EnumerateDeviceExtensionProperties(dev, nil, &dev_extension_count, &dev_extensions[0])
		for ext in &dev_extensions {
			if string(cstring(&ext.extensionName[0])) == string(vk.KHR_SWAPCHAIN_EXTENSION_NAME) {
				has_extension = true
			}
		}

		// Ensure the device is a discrete GPU
		device_properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(dev, &device_properties)
		is_discrete := (device_properties.deviceType == .DISCRETE_GPU)

		// Ensure the device has a queue supporting presentation
		is_present: b32
		queue_family_count: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(dev, &queue_family_count, nil)
		queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
		defer delete(queue_families)
		vk.GetPhysicalDeviceQueueFamilyProperties(dev, &queue_family_count, &queue_families[0])
		for family, i in queue_families {
			vk.GetPhysicalDeviceSurfaceSupportKHR(dev, u32(i), surface, &is_present)
			if (.GRAPHICS in family.queueFlags) && is_present {
				graphics_index = u32(i)
				break
			}
		}

		// Choose the device 
		if is_discrete && has_extension && is_present {
			gpu_found = true
			gpu = dev
			break
		}
	}
	if !gpu_found {
		panic("Failed to find appropriate physical device")
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
		panic("Failed to create device")
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
	using engine
	vk.DestroyDevice(device, nil)
	vk.DestroySurfaceKHR(instance, surface, nil)
	vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
	vk.DestroyInstance(instance, nil)
	glfw.DestroyWindow(window)
	glfw.Terminate()
}

main :: proc() {
	engine := create_engine()
	defer destroy_engine(&engine)

	for !glfw.WindowShouldClose(engine.window) {
		glfw.PollEvents()
	}
}
