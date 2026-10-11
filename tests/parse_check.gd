extends Node
## Loads every project script with autoloads present so parse/compile errors surface in one run.
func _ready() -> void:
	var failed := 0
	var stack := ["res://"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			if sub.begins_with(".") or sub in ["android", "android_plugin", "build"]:
				continue
			stack.append(dir_path.path_join(sub))
		for file in dir.get_files():
			if file.ends_with(".gd") and file != "parse_check.gd":
				var path := dir_path.path_join(file)
				var script: Script = load(path)
				if script == null or not script.can_instantiate():
					failed += 1
					print("PARSE_FAIL ", path)
	print("PARSE_CHECK failures=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)
