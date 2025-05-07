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
var show_data_points = true  # Toggle for showing data points

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

# Add after the existing variables
var coordinate_test_window: Window
var test_points = []  # Array to store test points

# Create a custom GridDrawer class
class GridDrawer extends Node2D:
	var parent
	
	func _init(parent_node):
		parent = parent_node
	
	func _draw():
		if parent.grid_data.size() == 0:
			return
			
		# First, draw the entire map border
		var map_bounds = Rect2(
			Vector2(0, 0),  # Position in local coordinates
			Vector2(parent.get_viewport_rect().size)  # Full viewport size
		)
		draw_rect(map_bounds, Color(0.1, 0.1, 0.1, 0.2), false, 2.0)
		
		# Draw all cells in a single pass to ensure consistency
		for cell in parent.grid_data:
			# Get exact screen position based on geographic coordinates
			var pos = parent.get_exact_screen_pos(cell.lat, cell.lon)
			
			# Draw the filled cell
			var cell_size = parent.get_cell_size()
			# Ensure perfect alignment between cell and data point
			var cell_rect = Rect2(Vector2(pos.x - cell_size.x/2, pos.y - cell_size.y/2), cell_size)
			var color = parent.get_ceiling_color(cell.ceiling)
			draw_rect(cell_rect, color, true)
			
			# Draw the cell border
			draw_rect(cell_rect, Color.BLACK, false, 1.0)
			
			# Draw data point
			if parent.show_data_points:
				var dot_size = 3.0
				draw_circle(pos, dot_size, Color(0, 0, 0, 1))
		
		# Draw test points
		for point in parent.test_points:
			var pos = parent.get_exact_screen_pos(point.lat, point.lon)
			draw_circle(pos, 5.0, Color(1, 0, 0, 1))  # Red dot for test points

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
	
	# Add Show/Hide Points button
	var show_points_button = Button.new()
	show_points_button.text = "Toggle Data Points"
	show_points_button.pressed.connect(_on_toggle_points_pressed)
	$UI/ZoomControls.add_child(show_points_button)
	
	# Add Lat Lon Test button
	var test_button = Button.new()
	test_button.text = "Lat Lon Test"
	test_button.pressed.connect(_on_test_button_pressed)
	$UI/ZoomControls.add_child(test_button)
	
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
		calculate_grid_spacing()  # Calculate grid spacing after loading data
	else:
		print("Failed to open file")

# Calculate the exact screen position for geographic coordinates
func get_exact_screen_pos(lat, lon):
	# Normalize coordinates to 0-1 range
	var norm_lat = 1.0 - ((lat - MIN_LAT) / LAT_RANGE)  # Flip latitude (north is up)
	var norm_lon = (lon - MIN_LON) / LON_RANGE
	
	# Get viewport size
	var viewport_size = get_viewport_rect().size
	
	# Calculate base position (unzoomed, unshifted)
	# Use exact proportional scaling to ensure points align with grid cells
	var base_x = norm_lon * viewport_size.x * 0.9 + viewport_size.x * 0.05
	var base_y = norm_lat * viewport_size.y * 0.9 + viewport_size.y * 0.05
	
	# Create global position vector (in world space)
	return Vector2(base_x, base_y)

# Get the current cell size based on zoom level
func get_cell_size():
	var viewport_size = get_viewport_rect().size
	
	# If we have calculated grid spacing, use it
	if grid_dimensions.has("lat_spacing") and grid_dimensions.has("lon_spacing"):
		# Convert lat/lon differences to screen pixels
		var norm_lat_diff = grid_dimensions.lat_spacing / LAT_RANGE
		var norm_lon_diff = grid_dimensions.lon_spacing / LON_RANGE
		
		var lat_size = norm_lat_diff * viewport_size.y * 0.9
		var lon_size = norm_lon_diff * viewport_size.x * 0.9
		
		# Use full width (or slightly wider) to eliminate gaps between columns
		# Keep the improved height
		return Vector2(lon_size * 1.02, lat_size * 1.25)
	else:
		# Fallback with similar adjustments
		var base_width = viewport_size.x * 0.9 / LON_MINUTES * 1.02
		var base_height = (viewport_size.y * 0.9 / LAT_MINUTES) * 0.625
		return Vector2(base_width, base_height)

# Reset the old methods to avoid conflicts
func calculate_transform():
	return null

func get_geo_cell_rect(lat, lon, transform = null):
	return Rect2()

func geo_to_screen(lat, lon):
	return get_exact_screen_pos(lat, lon)

func get_map_bounds(screen_rect):
	return Rect2(Vector2.ZERO, screen_rect)
	
func get_cell_rect(lat, lon):
	var pos = get_exact_screen_pos(lat, lon)
	var size = get_cell_size()
	return Rect2(Vector2(pos.x - size.x/2, pos.y - size.y/2), size)

func latlon_to_position(lat, lon):
	return get_exact_screen_pos(lat, lon)

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

func _on_toggle_points_pressed():
	show_data_points = !show_data_points
	grid_drawer.queue_redraw()

# Add this function after _ready()
func calculate_grid_spacing():
	# Initialize with large values
	var min_lat_diff = 999.0
	var min_lon_diff = 999.0
	
	# Sample data points to find typical spacing
	for i in range(grid_data.size()):
		for j in range(i+1, grid_data.size()):
			var lat_diff = abs(grid_data[i].lat - grid_data[j].lat)
			var lon_diff = abs(grid_data[i].lon - grid_data[j].lon)
			
			# Only consider if they're close enough to be neighbors (adjust threshold as needed)
			if lat_diff > 0 and lat_diff < 0.1:  # Assuming neighbors are within 0.1 degrees
				min_lat_diff = min(min_lat_diff, lat_diff)
			
			if lon_diff > 0 and lon_diff < 0.1:
				min_lon_diff = min(min_lon_diff, lon_diff)
	
	print("Minimum latitude difference: ", min_lat_diff)
	print("Minimum longitude difference: ", min_lon_diff)
	
	# Store for later use
	grid_dimensions["lat_spacing"] = min_lat_diff
	grid_dimensions["lon_spacing"] = min_lon_diff 

func setup_ui() -> void:
	# Connect button signals
	$UI/ZoomControls/ZoomInButton.pressed.connect(_on_zoom_in_pressed)
	$UI/ZoomControls/ZoomOutButton.pressed.connect(_on_zoom_out_pressed)
	$UI/ZoomControls/ResetButton.pressed.connect(_on_reset_view_pressed)
	
	# Add Show/Hide Points button
	var show_points_button = Button.new()
	show_points_button.text = "Toggle Data Points"
	show_points_button.pressed.connect(_on_toggle_points_pressed)
	$UI/ZoomControls.add_child(show_points_button)
	
	# Add Lat Lon Test button
	var test_button = Button.new()
	test_button.text = "Lat Lon Test"
	test_button.pressed.connect(_on_test_button_pressed)
	$UI/ZoomControls.add_child(test_button)
	
	# Make UI elements independent of camera
	$UI.top_level = true

func _on_test_button_pressed() -> void:
	if coordinate_test_window == null:
		# Create the coordinate test window
		coordinate_test_window = preload("res://coordinate_test_window.tscn").instantiate()
		coordinate_test_window.coordinate_submitted.connect(_on_coordinate_submitted)
		add_child(coordinate_test_window)
		coordinate_test_window.popup_centered()
	else:
		coordinate_test_window.show()
		coordinate_test_window.popup_centered()

func _on_coordinate_submitted(lat: float, lon: float) -> void:
	# Add the test point
	test_points.append({"lat": lat, "lon": lon})
	grid_drawer.queue_redraw() 
