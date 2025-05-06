extends Node2D

# Constants for grid cell size and display
const MINUTE_IN_DEGREES = 1.0/60.0  # 1 minute = 1/60 of a degree
const MIN_LAT = 40.55417343
const MAX_LAT = 40.88750683
const MIN_LON = -73.99583928
const MAX_LON = -73.5958392
const LAT_RANGE = MAX_LAT - MIN_LAT
const LON_RANGE = MAX_LON - MIN_LON
# Calculate how many 1-minute cells fit in our lat/lon range
const LAT_MINUTES = LAT_RANGE / MINUTE_IN_DEGREES
const LON_MINUTES = LON_RANGE / MINUTE_IN_DEGREES

# Zoom and pan variables
var zoom_level = 1.0
var zoom_min = 0.5
var zoom_max = 3.0
var zoom_step = 0.1
var panning = false
var last_mouse_position = Vector2()
var pan_speed = 10.0  # Speed for keyboard panning

# Colors for ceiling values
var ceiling_colors = {
	0: Color(1, 0, 0, 1.0),       # Red for no fly zones (fully opaque)
	50: Color(1, 0.5, 0, 1.0),    # Orange for very low altitude
	100: Color(1, 1, 0, 1.0),     # Yellow for low altitude
	200: Color(0.5, 1, 0, 1.0),   # Yellow-green for medium altitude
	300: Color(0, 1, 0.5, 1.0),   # Green-blue for high altitude
	400: Color(0, 1, 0, 1.0)      # Green for max altitude
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
		
		# Calculate cell dimensions in screen space
		var screen_rect = parent.get_viewport_rect().size
		var data_aspect_ratio = parent.LON_RANGE / parent.LAT_RANGE
		var screen_aspect_ratio = screen_rect.x / screen_rect.y
		
		var grid_width
		var grid_height
		var x_offset
		var y_offset
		
		# Adjust scaling to maintain geographic proportions
		if data_aspect_ratio > screen_aspect_ratio:
			# Width limited by screen width
			grid_width = screen_rect.x * 0.9
			grid_height = grid_width / data_aspect_ratio
			x_offset = screen_rect.x * 0.05
			y_offset = (screen_rect.y - grid_height) / 2
		else:
			# Height limited by screen height
			grid_height = screen_rect.y * 0.9
			grid_width = grid_height * data_aspect_ratio
			y_offset = screen_rect.y * 0.05
			x_offset = (screen_rect.x - grid_width) / 2
		
		# Calculate size of one minute cell
		var minute_cell_width = grid_width / parent.LON_MINUTES
		var minute_cell_height = grid_height / parent.LAT_MINUTES
		
		# Store these for later use
		parent.grid_dimensions = {
			"width": grid_width,
			"height": grid_height,
			"x_offset": x_offset,
			"y_offset": y_offset,
			"cell_width": minute_cell_width,
			"cell_height": minute_cell_height
		}
		
		# Draw all cells first
		for cell in parent.grid_data:
			var pos = parent.latlon_to_position(cell.lat, cell.lon)
			var color = parent.get_ceiling_color(cell.ceiling)
			
			# Calculate cell size (1 minute x 1 minute, scaled by zoom)
			var cell_width = minute_cell_width * parent.zoom_level
			var cell_height = minute_cell_height * parent.zoom_level
			var cell_size = Vector2(cell_width, cell_height)
			
			# Draw the filled cell
			draw_rect(Rect2(pos - cell_size/2, cell_size), color, true)
		
		# Then draw all cell borders
		for cell in parent.grid_data:
			var pos = parent.latlon_to_position(cell.lat, cell.lon)
			
			# Calculate cell size (1 minute x 1 minute, scaled by zoom)
			var cell_width = minute_cell_width * parent.zoom_level
			var cell_height = minute_cell_height * parent.zoom_level
			var cell_size = Vector2(cell_width, cell_height)
			
			# Draw the cell border (black outline)
			var line_width = max(1.0, 0.5 * parent.zoom_level)
			draw_rect(Rect2(pos - cell_size/2, cell_size), Color.BLACK, false, line_width)
		
		# Finally draw the map border (thicker and on top of everything)
		var map_rect = Rect2(
			Vector2(x_offset, y_offset) * parent.zoom_level + (parent.camera.position - (screen_rect/2) * parent.zoom_level),
			Vector2(grid_width, grid_height) * parent.zoom_level
		)
		draw_rect(map_rect, Color(0, 0, 0, 1), false, 2.0 * parent.zoom_level)

# Grid drawer instance
var grid_drawer

# Store grid dimensions for calculations
var grid_dimensions = {}

func _ready():
	# Set window size to 1920x1080 (Full HD)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(DisplayServer.screen_get_position() + (DisplayServer.screen_get_size() - Vector2i(1920, 1080)) / 2)
	
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

func _process(delta):
	# Handle keyboard arrow keys for panning
	var pan_direction = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		pan_direction.y += 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		pan_direction.y -= 1
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		pan_direction.x += 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		pan_direction.x -= 1
	
	if pan_direction != Vector2.ZERO:
		# Apply panning
		camera.position += pan_direction * pan_speed * (1 / zoom_level)
		grid_drawer.queue_redraw()

func _input(event):
	# Handle mouse wheel zooming
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(zoom_step)
			grid_drawer.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-zoom_step)
			grid_drawer.queue_redraw()
		# Handle panning with left OR middle mouse button
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
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
	
	# Get screen dimensions
	var screen_width = get_viewport_rect().size.x
	var screen_height = get_viewport_rect().size.y
	
	# Calculate aspect ratios
	var data_aspect_ratio = LON_RANGE / LAT_RANGE
	var screen_aspect_ratio = screen_width / screen_height
	
	var grid_width
	var grid_height
	var x_offset
	var y_offset
	
	# Adjust scaling to maintain geographic proportions
	if data_aspect_ratio > screen_aspect_ratio:
		# Width limited by screen width
		grid_width = screen_width * 0.9
		grid_height = grid_width / data_aspect_ratio
		x_offset = screen_width * 0.05
		y_offset = (screen_height - grid_height) / 2
	else:
		# Height limited by screen height
		grid_height = screen_height * 0.9
		grid_width = grid_height * data_aspect_ratio
		y_offset = screen_height * 0.05
		x_offset = (screen_width - grid_width) / 2
	
	# Calculate position with proper scaling
	var x = norm_lon * grid_width + x_offset
	var y = norm_lat * grid_height + y_offset
	
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
