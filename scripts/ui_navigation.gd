extends Node

const MODALS := ["GameSetup", "GraphModal", "CampaignDialog", "ResearchDetails", "VictoryDialog", "DefeatDialog", "QuitConfirmOverlay", "DeleteConfirmOverlay"]

func _ready() -> void:
 # Disable Godot's default focus/menu navigation, including native PopupMenu.
 # Text-caret actions and the game's physical-key shortcuts remain separate.
 for action in [&"ui_focus_next", &"ui_focus_prev", &"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
  InputMap.action_erase_events(action)
 get_tree().node_added.connect(_configure)

func _configure(node: Node) -> void:
 if node is BaseButton or node is Range:
  node.focus_mode = Control.FOCUS_NONE
 elif node is LineEdit or node is TextEdit:
  node.focus_mode = Control.FOCUS_CLICK
 if node is Popup and not node.has_meta("ui_navigation_ready"):
  node.set_meta("ui_navigation_ready", true)
  node.window_input.connect(_popup_input.bind(node))
  node.popup_hide.connect(_popup_hidden.bind(node))

func _popup_hidden(popup: Popup) -> void:
 if popup.get_meta("restore_after_nested_cancel", false):
  popup.remove_meta("restore_after_nested_cancel")
  _reopen.call_deferred(weakref(popup))

func _reopen(reference: WeakRef) -> void:
 var popup: Popup = reference.get_ref()
 if is_instance_valid(popup) and popup.is_inside_tree():
  popup.popup_centered()
  if popup.has_method("close_library"):
   popup.search.grab_focus()

func _popup_input(event: InputEvent, popup: Popup) -> void:
 if not event is InputEventKey or not event.pressed or event.echo:
  return
 if event.keycode == KEY_TAB:
  popup.set_input_as_handled()
  return
 if event.keycode != KEY_ESCAPE:
  return
 var nested := false
 if popup.has_method("close_library") and popup.delete_confirmation.visible:
  nested = true
  popup._cancel_delete()
 elif popup.has_method("_on_quit_cancelled") and popup.quit_confirmation_overlay.visible:
  nested = true
  popup._on_quit_cancelled()
 if nested:
  popup.set_meta("restore_after_nested_cancel", true)
 if popup.has_method("close_library") and not nested:
  popup.close_library()
 else:
  popup.hide()
 popup.set_input_as_handled()

func _find_modal(node: Node) -> Control:
 if node is Window or node.is_queued_for_deletion() or (node is Control and not node.is_visible_in_tree()):
  return null
 var result: Control = node if node is Control and (str(node.name) in MODALS or node.is_in_group("modal_ui")) else null
 for child in node.get_children():
  var candidate := _find_modal(child)
  if candidate != null and (result == null or candidate.z_index >= result.z_index):
   result = candidate
 return result

func _find_popup(node: Node) -> Popup:
 if node is Popup and node.visible:
  return node
 for child in node.get_children():
  var popup := _find_popup(child)
  if popup != null:
   return popup
 return null

func _close_button(node: Node) -> BaseButton:
 if node is Control and not node.is_visible_in_tree():
  return null
 if node is BaseButton and not node.disabled and (node.name == &"CloseX" or (node is Button and node.text in ["CLOSE", "CLOSE / SKIP", "CANCEL", "BACK TO FLEET", "CONTINUE"])):
  return node
 for child in node.get_children():
  var button := _close_button(child)
  if button != null:
   return button
 return null

func _input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
  get_viewport().set_input_as_handled()
  return
 var scene := get_tree().current_scene
 if scene == null:
  return
 var modal := _find_modal(scene)
 if event is InputEventMouseButton and modal != null and not modal.get_global_rect().has_point(event.position):
  get_viewport().set_input_as_handled()
  return
 if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
  return
 var popup := _find_popup(scene)
 if popup != null:
  _popup_input(event, popup)
  get_viewport().set_input_as_handled()
 elif modal != null:
  var button := _close_button(modal)
  if button != null:
   button.pressed.emit()
   get_viewport().set_input_as_handled()
 else:
  var owner := get_tree().root.gui_get_focus_owner()
  if owner != null:
   owner.release_focus()
