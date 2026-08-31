extends SceneTree


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("Не удалось загрузить главную сцену.")
		quit(1)
		return

	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	var image := root.get_texture().get_image()
	var output_path := "res://tmp/graybox-smoke.png"
	var error := image.save_png(output_path)
	if error == OK:
		print("CAPTURED: ", ProjectSettings.globalize_path(output_path))
	else:
		push_error("Не удалось сохранить кадр: %s" % error_string(error))
	quit(0 if error == OK else 1)
