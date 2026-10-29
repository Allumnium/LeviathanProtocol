class_name ShipLibraryDialog
extends PopupPanel

signal design_selected(design_name: String, design: Ship)

const PREVIEW = preload("res://scripts/ship_design_preview.gd")
const MATERIAL_ICONS: Array[Texture2D] = [
	preload("res://assets/ui/icons/red_square.png"),
	preload("res://assets/ui/icons/blue_square.png"),
	preload("res://assets/ui/icons/green_square.png"),
	preload("res://assets/core.png"),
]
const PAGE_SIZE := 3

@onready var title_label: Label = $Contents/Title
@onready var search: LineEdit = $Contents/SearchRow/Search
@onready var close_button: TextureButton = $CloseX
@onready var rows: VBoxContainer = $Contents/ScrollContainer/SavedDesignRows
@onready var empty_label: Label = $Contents/ScrollContainer/SavedDesignRows/EmptyDesignsLabel
@onready var back_button: Button = $Contents/Pager/PreviousPageButton
@onready var page_label: Label = $Contents/Pager/PageLabel
@onready var forward_button: Button = $Contents/Pager/ForwardButton
@onready var status_label: Label = $Contents/StatusLabel
@onready var delete_confirmation: Control = $DeleteConfirmOverlay
@onready var delete_confirmation_label: Label = (
	$DeleteConfirmOverlay/CenterContainer/ConfirmationPanel/Contents/WarningLabel
)
@onready var confirm_delete_button: Button = (
	$DeleteConfirmOverlay/CenterContainer/ConfirmationPanel/Contents/ButtonCenter/DeleteButton
)
@onready var cancel_delete_button: TextureButton = (
	$DeleteConfirmOverlay/CenterContainer/ConfirmationPanel/CloseX
)

var action_text := "SELECT"
var page := 0
var choices: Array[Dictionary] = []
var selection_validator: Callable
var fleet_slot_role := "regular"
var _pending_delete_name := ""


func _ready() -> void:
	close_button.pressed.connect(close_library)
	# Close on mouse-down as well, so an active LineEdit cannot consume the
	# first click merely to relinquish focus.
	close_button.button_down.connect(close_library)
	popup_hide.connect(_on_popup_hide)
	search.text_changed.connect(func(_text: String) -> void:
		page = 0
		_refresh_rows())
	confirm_delete_button.pressed.connect(_confirm_delete)
	cancel_delete_button.pressed.connect(_cancel_delete)
	GameState.tile_inventory_changed.connect(refresh_library)
	back_button.pressed.connect(func() -> void:
		page -= 1
		_refresh_rows())
	forward_button.pressed.connect(func() -> void:
		page += 1
		_refresh_rows())
	GameState.design_library_changed.connect(refresh_library)
	for button in [back_button, forward_button]:
		_style_pager_button(button)
	refresh_library()


func open_library(new_action_text: String, validator: Callable = Callable()) -> void:
	action_text = new_action_text.to_upper()
	selection_validator = validator
	title_label.text = "%s SHIP DESIGN" % action_text
	title_label.visible = action_text != "SELECT"
	search.text = ""
	status_label.text = ""
	status_label.visible = false
	_cancel_delete()
	page = 0
	refresh_library()
	popup_centered(Vector2i(480, 255))
	call_deferred("_clear_initial_focus")


func _clear_initial_focus() -> void:
	if is_instance_valid(search):
		search.grab_focus()


func close_library() -> void:
	hide()


func _on_popup_hide() -> void:
	_cancel_delete()


func refresh_library() -> void:
	if not is_node_ready():
		return
	choices.clear()
	for entry in GameState.get_visible_ship_designs():
		var blueprint := Ship.new()
		if blueprint.load_design_data(entry.ship):
			choices.append({"name": entry.name, "design": blueprint})
	_refresh_rows()


func _refresh_rows() -> void:
	for child in rows.get_children():
		if child != empty_label:
			child.queue_free()
	var filtered: Array[Dictionary] = []
	var query := search.text.strip_edges().to_lower()
	for choice in choices:
		if query.is_empty() or str(choice.name).to_lower().contains(query):
			filtered.append(choice)
	var page_count := maxi(1, ceili(filtered.size() / float(PAGE_SIZE)))
	page = clampi(page, 0, page_count - 1)
	page_label.text = "%d / %d" % [page + 1, page_count]
	back_button.visible = page_count > 1
	page_label.visible = page_count > 1
	forward_button.visible = page_count > 1
	back_button.disabled = page == 0
	forward_button.disabled = page == page_count - 1
	empty_label.visible = filtered.is_empty()
	for choice in filtered.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE):
		rows.add_child(_create_row(choice))


func _create_row(choice: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.theme_type_variation = &"LibraryRow"
	var contents := HBoxContainer.new()
	contents.add_theme_constant_override("separation", 6)
	row.add_child(contents)
	var preview := PREVIEW.new()
	preview.custom_minimum_size = Vector2(50, 36)
	preview.set_ship(choice.design)
	contents.add_child(preview)
	var name_label := Label.new()
	name_label.text = str(choice.name).to_upper()
	name_label.custom_minimum_size.x = 90
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	contents.add_child(name_label)
	var costs := HBoxContainer.new()
	costs.add_theme_constant_override("separation", 3)
	costs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_child(costs)
	var counts := GameState.get_design_material_costs(choice.design)
	for category in range(MATERIAL_ICONS.size()):
		if counts[category] > 0:
			_add_cost_item(costs, MATERIAL_ICONS[category], counts[category])
	var action := Button.new()
	var assigned_slot := GameState.fleet_design_slots.find(str(choice.name))
	if GameState.campaign_active:
		if fleet_slot_role == "regular":
			assigned_slot = GameState.roster_state.active.find(GameState.family_for_design(choice.design))
			if GameState.family_for_design(choice.design).is_empty():
				assigned_slot = -1
		else:
			assigned_slot = (3 if fleet_slot_role == "science" else 4) if GameState.roster_state.support_names[fleet_slot_role] == choice.name else -1
	var is_assigned := action_text == "SELECT" and assigned_slot >= 0
	if is_assigned and GameState.campaign_active and fleet_slot_role == "regular":
		var selected: Ship = GameState.slot_blueprint(assigned_slot)
		is_assigned = selected != null and FleetRules.fingerprint(selected) == FleetRules.fingerprint(choice.design)
	action.text = "ASSIGNED TO SLOT %d" % (assigned_slot + 1) if is_assigned else action_text
	action.custom_minimum_size.x = 112 if is_assigned else 68
	_style_button(action)
	var validation_message := ""
	if selection_validator.is_valid():
		validation_message = str(selection_validator.call(choice.design))
	action.disabled = is_assigned
	if not validation_message.is_empty() and not is_assigned:
		action.text = "DETAILS"
	action.pressed.connect(func() -> void:
		if not validation_message.is_empty():
			status_label.text = str(choice.name) + ": " + validation_message
			status_label.show()
			return
		design_selected.emit(choice.name, choice.design)
		hide())
	contents.add_child(action)
	var remove := TextureButton.new()
	remove.custom_minimum_size = Vector2(24, 24)
	remove.texture_normal = _trash_icon(Color(0.93, 0.45, 0.45))
	remove.texture_hover = _trash_icon(Color(1.0, 0.68, 0.62))
	remove.texture_pressed = _trash_icon(Color(0.65, 0.2, 0.2))
	remove.ignore_texture_size = true
	remove.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	remove.disabled = choice.name == "Drone"
	remove.modulate.a = 0.0 if remove.disabled else 1.0
	remove.mouse_filter = Control.MOUSE_FILTER_IGNORE if remove.disabled else Control.MOUSE_FILTER_STOP
	remove.pressed.connect(func() -> void:
		_prompt_delete(str(choice.name)))
	contents.add_child(remove)
	return row


func _prompt_delete(design_name: String) -> void:
	_pending_delete_name = design_name
	delete_confirmation_label.text = (
		"ARE YOU SURE YOU WANT TO DELETE\nTHE DESIGN FOR %s?" % design_name.to_upper()
	)
	delete_confirmation.show()


func _cancel_delete() -> void:
	_pending_delete_name = ""
	if is_instance_valid(delete_confirmation):
		delete_confirmation.hide()


func _confirm_delete() -> void:
	var design_name := _pending_delete_name
	_cancel_delete()
	if design_name.is_empty() or GameState.delete_saved_ship_design(design_name):
		return
	status_label.text = "Could not delete the saved design."
	status_label.visible = true


func _add_cost_item(row: HBoxContainer, icon: Texture2D, amount: int) -> void:
	var texture := TextureRect.new()
	texture.custom_minimum_size = Vector2(10, 10)
	texture.texture = icon
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(texture)
	var label := Label.new()
	label.text = str(amount)
	row.add_child(label)


static func _style_button(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 30)


static func _style_pager_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(30, 26)
	button.theme_type_variation = &"IconButton"


static func _trash_icon(color: Color) -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="16"><path d="M2 4h10M5 4V2h4v2M3 5l1 9h6l1-9M6 6v6M8 6v6" fill="none" stroke="#%s" stroke-width="1.5" stroke-linejoin="round"/></svg>' % color.to_html(false))
	return ImageTexture.create_from_image(image)
