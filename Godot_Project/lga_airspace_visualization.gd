extends Node2D

# Constants for grid cell size and display
const CELL_SIZE = Vector2(24, 24)  # Slightly larger cells for better visibility
const MIN_LAT = 40.55417343
const MAX_LAT = 40.88750683
const MIN_LON = -73.99583928
const MAX_LON = -73.5958392
const LAT_RANGE = MAX_LAT - MIN_LAT
const LON_RANGE = MAX_LON - MIN_LON

# Zoom and pan variables
var zoom_level = 1.0
var zoom_min = 0.5
var zoom_max = 3.0
var zoom_step = 0.1
var panning = false
var last_mouse_position = Vector2()

# Colors for ceiling values
var ceiling_colors = {
	0: Color(1, 0, 0, 0.8),       # Red for no fly zones (more opaque)
	50: Color(1, 0.5, 0, 0.8),    # Orange for very low altitude
	100: Color(1, 1, 0, 0.8),     # Yellow for low altitude
	200: Color(0.5, 1, 0, 0.8),   # Yellow-green for medium altitude
	300: Color(0, 1, 0.5, 0.8),   # Green-blue for high altitude
	400: Color(0, 1, 0, 0.8)      # Green for max altitude
}

# Store grid data
var grid_data = []
@onready var camera = $Camera2D
@onready var grid_container = $GridContainer
var viewport_size = Vector2()

# Create a custom GridDrawer class
class GridDrawer extends Node2D:
	var parent
	
	func _init(parent_node):
		parent = parent_node
	
	func _draw():
		if parent.grid_data.size() == 0:
			return
			
		for cell in parent.grid_data:
			var pos = parent.latlon_to_position(cell.lat, cell.lon)
			var color = parent.get_ceiling_color(cell.ceiling)
			
			# Draw cell
			draw_rect(Rect2(pos - parent.CELL_SIZE/2, parent.CELL_SIZE), color)
			
			# Draw cell outline
			draw_rect(Rect2(pos - parent.CELL_SIZE/2, parent.CELL_SIZE), Color.BLACK, false, 1.0)

# Grid drawer instance
var grid_drawer

func _ready():
	# Store initial viewport size
	viewport_size = get_viewport_rect().size
	
	# Create and add the grid drawer
	grid_drawer = GridDrawer.new(self)
	grid_container.add_child(grid_drawer)
	
	load_airspace_data()
	
	# Connect button signals
	$UI/ZoomControls/ZoomInButton.pressed.connect(_on_zoom_in_pressed)
	$UI/ZoomControls/ZoomOutButton.pressed.connect(_on_zoom_out_pressed)
	$UI/ZoomControls/ResetButton.pressed.connect(_on_reset_view_pressed)
	
	# Make the UI elements independent of the camera
	$UI.top_level = true
	
	# Setup camera
	camera.position = viewport_size / 2
	
	# Initial update
	grid_drawer.queue_redraw()
	
	# Listen for window resize
	get_tree().root.size_changed.connect(_on_window_resize)

func _on_window_resize():
	# Update viewport size
	var new_viewport_size = get_viewport_rect().size
	
	# Adjust camera position to center
	camera.position = new_viewport_size / 2
	
	# Update the stored viewport size
	viewport_size = new_viewport_size
	
	# Redraw the grid
	grid_drawer.queue_redraw()
	
	# Update UI positions if needed
	$BackgroundMap.size = new_viewport_size
	$UI/InfoPanel.position.x = new_viewport_size.x - 300

func _input(event):
	# Handle mouse wheel zooming
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(zoom_step)
			grid_drawer.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-zoom_step)
			grid_drawer.queue_redraw()
		# Handle panning with middle mouse button
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				panning = true
				last_mouse_position = event.position
			else:
				panning = false
	
	# Handle panning with mouse movement
	if event is InputEventMouseMotion and panning:
		camera.position -= event.position - last_mouse_position
		last_mouse_position = event.position

func _on_zoom_in_pressed():
	_change_zoom(zoom_step)
	grid_drawer.queue_redraw()

func _on_zoom_out_pressed():
	_change_zoom(-zoom_step)
	grid_drawer.queue_redraw()

func _on_reset_view_pressed():
	# Reset zoom and camera position
	zoom_level = 1.0
	camera.position = get_viewport_rect().size / 2  # Center of screen
	camera.zoom = Vector2(zoom_level, zoom_level)
	grid_drawer.queue_redraw()

func _change_zoom(amount):
	zoom_level = clamp(zoom_level + amount, zoom_min, zoom_max)
	camera.zoom = Vector2(zoom_level, zoom_level)

func load_airspace_data():
	var file = FileAccess.open("res://Data/filtered_data_LGA.csv", FileAccess.READ)
	if file:
		# Skip header
		var header = file.get_line()
		
		while !file.eof_reached():
			var line = file.get_line()
			if line.strip_edges() == "":
				continue
				
			var parts = line.split(",")
			if parts.size() >= 3:
				var ceiling = int(parts[0])
				var lat = float(parts[1])
				var lon = float(parts[2])
				
				grid_data.append({
					"ceiling": ceiling,
					"lat": lat,
					"lon": lon
				})
		
		print("Loaded ", grid_data.size(), " grid cells")
	else:
		print("Failed to open file")

# Convert latitude and longitude to screen position
func latlon_to_position(lat, lon):
	# Normalize coordinates to 0-1 range
	var norm_lat = (lat - MIN_LAT) / LAT_RANGE
	var norm_lon = (lon - MIN_LON) / LON_RANGE
	
	# Flip latitude (north is up)
	norm_lat = 1.0 - norm_lat
	
	# Convert to screen coordinates
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	# Use minimum dimension to ensure grid is properly scaled regardless of window proportions
	var min_dimension = min(screen_width, screen_height)
	var scale_factor = min_dimension / max(LAT_RANGE, LON_RANGE) * 0.85 # 85% of the smaller dimension
	
	# Calculate centered grid
	var grid_width = LON_RANGE * scale_factor
	var grid_height = LAT_RANGE * scale_factor
	var x = norm_lon * grid_width + (screen_width - grid_width) / 2
	var y = norm_lat * grid_height + (screen_height - grid_height) / 2
	
	return Vector2(x, y)

# Get color based on ceiling value
func get_ceiling_color(ceiling):
	if ceiling_colors.has(ceiling):
		return ceiling_colors[ceiling]
	
	# Find closest ceiling value as fallback
	var closest_ceiling = 0
	var min_diff = 99999
	
	for c in ceiling_colors.keys():
		var diff = abs(c - ceiling)
		if diff < min_diff:
			min_diff = diff
			closest_ceiling = c
	
	return ceiling_colors[closest_ceiling] 
