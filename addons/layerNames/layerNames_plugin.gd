@tool
extends EditorPlugin

const OUTPUT_PATH := "res://addons/layerNames/generated/"
const OUTPUT_FILE_GDSCRIPT := OUTPUT_PATH + "layerNames.gd"
const OUTPUT_FILE_CSHARP := OUTPUT_PATH + "LayerNames.cs"
const SINGLETON_NAME := "LayerNames"
const CSHARP_NAMESPACE_DEFAULT := "ProjectLayerNames"
const SETTING_KEY_FORMAT := "layer_names/%s/layer_%s"
const OUTPUT_SETTING_KEY := "addons/project_layer_names/output"
const NAMESPACE_SETTING_KEY := "addons/project_layer_names/c#_namespace"
const INPUT_WAIT_SECONDS := 1.5
const VALID_IDENTIFIER_PATTERN := "[^a-z,A-Z,0-9,_,\\s]"
const BIT_SHIFT_OFFSET := 1

# Layer type definitions: layer_type -> max_count
const LAYER_TYPES := {
	"2d_render": 20,
	"2d_physics": 32,
	"2d_navigation": 32,
	"3d_render": 20,
	"3d_physics": 32,
	"3d_navigation": 32,
	"avoidance": 32
}

enum OutputLanguage {
	GDScript = 0,
	CSharp = 1,
	Both = 2
}

var previous_gdscript_hash := ""
var previous_csharp_hash := ""
var wait_tickets := 0
var layer_settings_cache := {}
var regex_cache := RegEx.new()

func _enter_tree() -> void:
	print("LayerNames plugin activated.")
	
	_register_project_settings()
	ProjectSettings.settings_changed.connect(_update_layer_names)
	
	DirAccess.make_dir_recursive_absolute(OUTPUT_PATH)
	
	regex_cache.compile(VALID_IDENTIFIER_PATTERN)
	
	_update_layer_names()

func _exit_tree() -> void:
	ProjectSettings.settings_changed.disconnect(_update_layer_names)
	remove_autoload_singleton(SINGLETON_NAME)
	layer_settings_cache.clear()

func _register_project_settings() -> void:
	if not ProjectSettings.has_setting(OUTPUT_SETTING_KEY):
		ProjectSettings.set_setting(OUTPUT_SETTING_KEY, OutputLanguage.GDScript)
		ProjectSettings.add_property_info({
			"name": OUTPUT_SETTING_KEY,
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": "GDScript,C#,Both",
			"default": OutputLanguage.GDScript
		})
		ProjectSettings.save()
		
	ProjectSettings.set_initial_value(OUTPUT_SETTING_KEY, OutputLanguage.GDScript)
		
	if not ProjectSettings.has_setting(NAMESPACE_SETTING_KEY):
		ProjectSettings.set_setting(NAMESPACE_SETTING_KEY, CSHARP_NAMESPACE_DEFAULT)
		ProjectSettings.add_property_info({
			"name": NAMESPACE_SETTING_KEY,
			"type": TYPE_STRING,
			"default": CSHARP_NAMESPACE_DEFAULT
		})
		ProjectSettings.save()

	ProjectSettings.set_initial_value(NAMESPACE_SETTING_KEY, CSHARP_NAMESPACE_DEFAULT)

func _update_layer_names() -> void:
	wait_tickets += 1
	var wait_number := wait_tickets
	await get_tree().create_timer(INPUT_WAIT_SECONDS).timeout
	if wait_number != wait_tickets: return
	
	layer_settings_cache.clear()
	
	var output_setting := ProjectSettings.get_setting(OUTPUT_SETTING_KEY, OutputLanguage.GDScript)
	
	match output_setting:
		OutputLanguage.GDScript:
			_generate_gdscript_file()
		OutputLanguage.CSharp:
			_generate_csharp_file()
		OutputLanguage.Both:
			_generate_csharp_file()
			_generate_gdscript_file()

func _write_to_file(file_path: String, content: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _generate_hash(content: String) -> String:
	return content.sha256_text()

func _generate_gdscript_file() -> void:
	var text_parts := PackedStringArray()
	text_parts.append("extends Node\n\n")
	
	for layer_type in LAYER_TYPES:
		text_parts.append(_create_enum_string(OutputLanguage.GDScript, layer_type, LAYER_TYPES[layer_type]))

	var current_text := "".join(text_parts)
	var current_hash := _generate_hash(current_text)
	if current_hash == previous_gdscript_hash:
		return

	print("Regenerating LayerNames GDScript enums")
	_write_to_file(OUTPUT_FILE_GDSCRIPT, current_text)
	add_autoload_singleton(SINGLETON_NAME, OUTPUT_FILE_GDSCRIPT)
	previous_gdscript_hash = current_hash

func _generate_csharp_file() -> void:
	var text_parts := PackedStringArray()
	var namespace_setting := ProjectSettings.get_setting(NAMESPACE_SETTING_KEY);

	text_parts.append("using Godot;\n\nnamespace ")
	text_parts.append(namespace_setting)
	text_parts.append(" {\n\tpublic partial class LayerNames : Node {\n\t\t\n")

	# Add singleton boilerplate
	text_parts.append(_generate_singleton_boilerplate())

	for layer_type in LAYER_TYPES:
		text_parts.append(_create_enum_string(OutputLanguage.CSharp, layer_type, LAYER_TYPES[layer_type]))

	text_parts.append("\t}\n}\n")

	var current_text := "".join(text_parts)
	var current_hash := _generate_hash(current_text)
	if current_hash == previous_csharp_hash:
		return

	print("Regenerating LayerNames C# enums")
	_write_to_file(OUTPUT_FILE_CSHARP, current_text)
	add_autoload_singleton(SINGLETON_NAME, OUTPUT_FILE_CSHARP)
	previous_csharp_hash = current_hash

func _generate_singleton_boilerplate() -> String:
	var boilerplate_parts := PackedStringArray()

	boilerplate_parts.append("\t\tprivate static LayerNames _instance;\n")
	boilerplate_parts.append("\t\tpublic static LayerNames Instance\n")
	boilerplate_parts.append("\t\t{\n")
	boilerplate_parts.append("\t\t\tget\n")
	boilerplate_parts.append("\t\t\t{\n")
	boilerplate_parts.append("\t\t\t\tif (_instance == null)\n")
	boilerplate_parts.append("\t\t\t\t\tGD.PrintErr(\"LayerNames singleton not initialized.\");\n")
	boilerplate_parts.append("\t\t\t\treturn _instance;\n")
	boilerplate_parts.append("\t\t\t}\n")
	boilerplate_parts.append("\t\t}\n")
	boilerplate_parts.append("\t\tpublic override void _Ready()\n")
	boilerplate_parts.append("\t\t{\n")
	boilerplate_parts.append("\t\t\tif (_instance == null)\n")
	boilerplate_parts.append("\t\t\t\t_instance = this;\n")
	boilerplate_parts.append("\t\t\telse if (_instance != this)\n")
	boilerplate_parts.append("\t\t\t\tQueueFree();\n")
	boilerplate_parts.append("\t\t}\n")
	boilerplate_parts.append("\t\tpublic override void _ExitTree()\n")
	boilerplate_parts.append("\t\t{\n")
	boilerplate_parts.append("\t\t\tif (_instance == this)\n")
	boilerplate_parts.append("\t\t\t\t_instance = null;\n")
	boilerplate_parts.append("\t\t}\n\n")

	return "".join(boilerplate_parts)

func _create_enum_string(language: OutputLanguage, layer_type: String, max_layer_count: int) -> String:
	var enum_name := _get_enum_name(layer_type)
	var enum_type := " : uint" if language == OutputLanguage.CSharp else ""
	var enum_indent := "\t\t" if language == OutputLanguage.CSharp else ""
	var entry_indent := "\t\t\t" if language == OutputLanguage.CSharp else "\t"
	var public_keyword := "public " if language == OutputLanguage.CSharp else ""
	
	var enum_parts := PackedStringArray()
	enum_parts.append("%s%senum " % [enum_indent, public_keyword])
	enum_parts.append(enum_name)
	enum_parts.append(enum_type)
	enum_parts.append(" {\n")
	enum_parts.append("%sNONE_NUM = 0,\n" % entry_indent)
	enum_parts.append("%sNONE_BIT = 0,\n" % entry_indent)
	
	for index in max_layer_count:
		var layer_number := index + 1
		var layer_name := _get_layer_name(layer_type, layer_number)
		enum_parts.append(_generate_enum_entry(language, layer_number, layer_name))
	
	enum_parts.append("%s}\n\n" % enum_indent)
	return "".join(enum_parts)

func _get_enum_name(layer_type: String) -> String:
	# Convert layer type to enum name (e.g., '2d_render' -> 'RENDER_2D')
	var parts := layer_type.split("_")
	parts.reverse()
	return _sanitise(" ".join(parts))

func _get_layer_name(layer_type: String, layer_number: int) -> String:
	var cache_key := "%s_%s" % [layer_type, layer_number]
	if not layer_settings_cache.has(cache_key):
		layer_settings_cache[cache_key] = ProjectSettings.get_setting(
			SETTING_KEY_FORMAT % [layer_type, layer_number]
		)
	return layer_settings_cache[cache_key]

func _generate_enum_entry(language: OutputLanguage, layer_number: int, layer_name: String) -> String:
	var key := _sanitise(layer_name)
	if not key:
		key = "LAYER_%s" % layer_number
	
	var entry_indent := "\t\t\t" if language == OutputLanguage.CSharp else "\t"
	var bit_value := 1 << (layer_number - BIT_SHIFT_OFFSET)
	
	var entry_parts := PackedStringArray()
	entry_parts.append("%s%s_NUM = %s,\n" % [entry_indent, key, layer_number])
	entry_parts.append("%s%s_BIT = %s,\n" % [entry_indent, key, bit_value])
	
	return "".join(entry_parts)

func _sanitise(input: String) -> String:
	if input.is_empty():
		return ""
	
	var output := regex_cache.sub(input.replace("-", "_"), "", true)
	output = output.to_snake_case().to_upper()

	return output if output.is_valid_identifier() else ""
