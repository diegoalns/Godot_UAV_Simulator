extends Node3D

const MIN_LAT = 40.55417343
const MAX_LAT = 40.88750683
const MIN_LON = -73.99583928
const MAX_LON = -73.5958392
const LAT_RANGE = MAX_LAT - MIN_LAT
const LON_RANGE = MAX_LON - MIN_LON

var ceiling_colors = {
	0: Color(1, 0, 0, 1.0),       # Red for no fly zones
	50: Color(1, 0.5, 0, 1.0),    # Orange for very low altitude
	100: Color(1, 1, 0, 1.0),     # Yellow for low altitude
	200: Color(0.5, 1, 0, 1.0),   # Yellow-green for medium altitude
	300: Color(0, 1, 0.5, 1.0),   # Green-blue for high altitude
	400: Color(0, 1, 0, 1.0)      # Green for max altitude
}

@onready var camera_pivot = $CameraPivot
@onready var camera = $CameraPivot/Camera3D

var orbit_sensitivity := 0.01
var pan_sensitivity := 0.05
var zoom_sensitivity := 2.0
var dragging_orbit := false
var dragging_pan := false
var last_mouse_pos := Vector2()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging_orbit = event.pressed
			last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging_pan = event.pressed
			last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.translate_object_local(Vector3(0, 0, -zoom_sensitivity))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.translate_object_local(Vector3(0, 0, zoom_sensitivity))
	elif event is InputEventMouseMotion:
		var delta = event.position - last_mouse_pos
		if dragging_orbit:
			camera_pivot.rotate_y(-delta.x * orbit_sensitivity)
			camera_pivot.rotate_x(-delta.y * orbit_sensitivity)
		elif dragging_pan:
			var right = camera.transform.basis.x
			var up = camera.transform.basis.y
			camera_pivot.translation -= (right * delta.x + up * -delta.y) * pan_sensitivity
		last_mouse_pos = event.position

func _ready():
	# Set window size to 1920x1080 (Full HD)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(DisplayServer.screen_get_position() + (DisplayServer.screen_get_size() - Vector2i(1920, 1080)) / 2)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90, 0, 0)
	add_child(light)
	# Place camera directly above the grid, looking straight down (God's view)
	camera.position = Vector3(0, 40, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0) # Look straight down
	load_airspace_data()

func load_airspace_data():
	var file = FileAccess.open("res://Data/filtered_data_LGA.csv", FileAccess.READ)
	if file:
		file.get_line() # skip header
		while not file.eof_reached():
			var line = file.get_line()
			if line.strip_edges() == "":
				continue
			var parts = line.split(",")
			if parts.size() >= 3:
				var ceiling = int(parts[0])
				var lat = float(parts[1])
				var lon = float(parts[2])
				add_cell_mesh(lat, lon, ceiling)
		file.close()
	else:
		print("Failed to open airspace data file.")

func add_cell_mesh(lat, lon, ceiling):
	print("Adding cell at lat: %s, lon: %s, ceiling: %s" % [lat, lon, ceiling])
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1, max(ceiling / 100.0, 0.1), 1) # Height based on ceiling, min height 0.1
	mesh_instance.mesh = box_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = get_ceiling_color(ceiling)
	mesh_instance.material_override = material

	# X-axis: west is left, east is right
	var x = ((lon - MIN_LON) / LON_RANGE) * 20 - 10
	# Z-axis: north is top, south is bottom
	var z = ((MAX_LAT - lat) / LAT_RANGE) * 20 - 10
	var y = box_mesh.size.y / 2
	mesh_instance.position = Vector3(x, y, z)

	add_child(mesh_instance)

func get_ceiling_color(ceiling):
	if ceiling_colors.has(ceiling):
		return ceiling_colors[ceiling]
	var closest = 0
	var min_diff = 99999
	for c in ceiling_colors.keys():
		var diff = abs(c - ceiling)
		if diff < min_diff:
			min_diff = diff
			closest = c
	return ceiling_colors[closest] 
