extends Window

signal coordinate_submitted(lat: float, lon: float)

@onready var lat_input = $VBoxContainer/LatInput
@onready var lon_input = $VBoxContainer/LonInput
@onready var show_button = $VBoxContainer/ShowButton

func _ready():
	show_button.pressed.connect(_on_show_pressed)
	close_requested.connect(_on_close_requested)

func _on_close_requested():
	hide()

func _on_show_pressed():
	var lat = float(lat_input.text)
	var lon = float(lon_input.text)
	
	# Validate coordinates
	if lat < 40.55417343 or lat > 40.88750683 or lon < -73.99583928 or lon > -73.5958392:
		# Show error message
		var error_dialog = AcceptDialog.new()
		add_child(error_dialog)
		error_dialog.dialog_text = "Coordinates out of bounds! Please enter valid LGA coordinates."
		error_dialog.popup_centered()
		return
	
	emit_signal("coordinate_submitted", lat, lon) 
