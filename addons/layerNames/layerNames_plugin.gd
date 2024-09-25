@tool
extends EditorPlugin

const OUTPUT_FILE := "res://addons/layerNames/layerNames.gd"
const SINGLETON_NAME := "LayerNames"
const SETTING_KEY_FORMAT := "layer_names/%s/layer_%s"
const RENDER_LAYER_COUNT := 20
const PHYSICS_LAYER_COUNT := 32
const NAVIGATION_LAYER_COUNT := 32
const AVOIDANCE_LAYER_COUNT := 32

const VALID_IDENTIFIER_PATTERN := "[^a-z,A-Z,0-9,\\s]"

var previous_text := ""

func _enter_tree() -> void:
	print("LayerNames plugin activated.")
	ProjectSettings.settings_changed.connect(_update_layer_names)
	_update_layer_names()
	
func _exit_tree() -> void:
	ProjectSettings.settings_changed.disconnect(_update_layer_names)
	remove_autoload_singleton(SINGLETON_NAME)
	
func _update_layer_names() -> void: 
	var render_layers_2d_enum_string : String = _create_enum_string("2d_render", RENDER_LAYER_COUNT)
	var physics_layers_2d_enum_string : String = _create_enum_string("2d_physics", PHYSICS_LAYER_COUNT)
	var navigation_layers_2d_enum_string : String = _create_enum_string("2d_navigation", NAVIGATION_LAYER_COUNT)
	
	var render_layers_3d_enum_string : String = _create_enum_string("3d_render", RENDER_LAYER_COUNT)
	var physics_layers_3d_enum_string : String = _create_enum_string("3d_physics", PHYSICS_LAYER_COUNT)
	var navigation_layers_3d_enum_string : String = _create_enum_string("3d_navigation", NAVIGATION_LAYER_COUNT)
	
	var avoidance_layers_enum_string : String = _create_enum_string("avoidance", AVOIDANCE_LAYER_COUNT)
	
	var current_text = "".join([
		"extends Node\n", 
		render_layers_2d_enum_string,
		physics_layers_2d_enum_string,
		navigation_layers_2d_enum_string,
		render_layers_3d_enum_string,
		physics_layers_3d_enum_string,
		navigation_layers_3d_enum_string,
		avoidance_layers_enum_string,
	])
	
	if current_text == previous_text:
		return
		
	print("Regenerating LayerNames enums")

	var file = FileAccess.open(OUTPUT_FILE, FileAccess.WRITE)
	file.store_string(current_text)
	file.close()
	previous_text = current_text
	
	add_autoload_singleton(SINGLETON_NAME, OUTPUT_FILE)
	
func _create_enum_string(layer_type : String, max_layer_count : int) -> String:
	var parts := layer_type.split("_")
	parts.reverse()
	
	var enum_name := _sanitise(" ".join(parts)) 
	var enum_text := ["enum ", enum_name," { \n"]
	
	for index in max_layer_count:
		var layer_number := str(index + 1)
		var name : String = ProjectSettings.get_setting(SETTING_KEY_FORMAT % [layer_type, layer_number])
		var value := 2 ** (index)
		var key := _sanitise(name)
		if !key:
			key = "LAYER_%s" % layer_number
			
		enum_text.push_back("%s = %s,\n" % [key, value])
		
	enum_text.push_back("}\n\n")
	
	return "".join(enum_text)

func _sanitise(input : String) -> String:
	var regex = RegEx.new()
	regex.compile(VALID_IDENTIFIER_PATTERN)

	var output = regex.sub(input, "", true)
	output = output.to_snake_case().to_upper()
	
	if output.is_valid_identifier():
		return output
	else:
		return ""
