extends Control

const SAVE_PATH = "user://standoff2_simulator_save.json"
const SERVER_URL = "https://stand-fall.onrender.com"

var gold: int = 0
var silver: int = 250
var inventory: Array = []

var is_rolling: bool = false
var current_item_name: String = ""
var current_is_box: bool = true
var winning_skin: Dictionary = {}
var roll_skins: Array = []
var card_width: float = 140.0
var card_gap: float = 10.0
var winning_index: int = 32
var win_glow_tween: Tween = null
var showing_boxes: bool = true

@onready var gold_label: Label = $UI/Header/Stats/GoldContainer/GoldLabel
@onready var silver_label: Label = $UI/Header/Stats/SilverContainer/SilverLabel
@onready var cases_panel: ScrollContainer = $UI/MainArea/CasesPanel
@onready var inventory_panel: ScrollContainer = $UI/MainArea/InventoryPanel
@onready var opener_panel: Panel = $UI/OpenerPanel
@onready var cases_tab_btn: Button = $UI/Header/Tabs/CasesTabBtn
@onready var inventory_tab_btn: Button = $UI/Header/Tabs/InventoryTabBtn
@onready var roll_container: Control = $UI/OpenerPanel/RollArea/RollContainer
@onready var win_popup_overlay: ColorRect = $UI/WinPopupOverlay
@onready var win_popup: Panel = $UI/WinPopup
@onready var win_weapon_label: Label = $UI/WinPopup/VBox/WeaponPanel/WeaponLabel
@onready var win_skin_label: Label = $UI/WinPopup/VBox/SkinLabel
@onready var win_rarity_label: Label = $UI/WinPopup/VBox/RarityLabel
@onready var inventory_grid: GridContainer = $UI/MainArea/InventoryPanel/VBox/GridContainer
@onready var inventory_empty_label: Label = $UI/MainArea/InventoryPanel/VBox/EmptyLabel
@onready var profile_btn: Button = $UI/Header/Tabs/ProfileBtn

var auth_scene_instance: Control = null
var logged_in_user: String = ""
var logged_in_id: String = ""

func _ready() -> void:
	load_game()
	roll_container.add_theme_constant_override("separation", int(card_gap))

	cases_tab_btn.pressed.connect(_on_cases_tab_pressed)
	inventory_tab_btn.pressed.connect(_on_inventory_tab_pressed)
	$UI/Header/Stats/ClickerButton.pressed.connect(_on_clicker_pressed)

	$UI/OpenerPanel/SpinBtn.pressed.connect(_start_roll)
	$UI/OpenerPanel/BackBtn.pressed.connect(_close_opener)

	$UI/WinPopup/VBox/Buttons/ClaimBtn.pressed.connect(_on_claim_pressed)
	$UI/WinPopup/VBox/Buttons/SellBtn.pressed.connect(_on_sell_instantly_pressed)

	if profile_btn:
		profile_btn.pressed.connect(_on_profile_pressed)

	$UI/MainArea/CasesPanel/VBox/SubTabs/BoxesBtn.pressed.connect(_on_boxes_subtab_pressed)
	$UI/MainArea/CasesPanel/VBox/SubTabs/CasesBtn.pressed.connect(_on_cases_subtab_pressed)

	_on_cases_tab_pressed()
	update_ui()

# --- ECONOMY & SAVE SYSTEM ---

func _get_save_path() -> String:
	if logged_in_user != "":
		return "user://save_" + logged_in_user.md5_text() + ".json"
	return SAVE_PATH

func save_game() -> void:
	var save_dict = {
		"gold": gold,
		"silver": silver,
		"inventory": inventory
	}
	var file = FileAccess.open(_get_save_path(), FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(save_dict))
		file.close()

func load_game() -> void:
	var path = _get_save_path()
	if not FileAccess.file_exists(path):
		gold = 0
		silver = 250
		inventory = []
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		var json = JSON.new()
		if json.parse(json_string) == OK:
			var data = json.data
			if data is Dictionary:
				gold = data.get("gold", 0)
				silver = data.get("silver", 250)
				inventory = data.get("inventory", [])

func _on_clicker_pressed() -> void:
	silver += 3
	update_ui()
	save_game()

# --- UI TAB SWITCHING ---

func _set_tab_active(is_cases: bool) -> void:
	if is_cases:
		cases_tab_btn.add_theme_color_override("font_color", Color.ORANGE)
		inventory_tab_btn.add_theme_color_override("font_color", Color.WHITE)
	else:
		inventory_tab_btn.add_theme_color_override("font_color", Color.ORANGE)
		cases_tab_btn.add_theme_color_override("font_color", Color.WHITE)
	profile_btn.add_theme_color_override("font_color", Color.WHITE)

func _on_cases_tab_pressed() -> void:
	cases_panel.visible = true
	inventory_panel.visible = false
	opener_panel.visible = false
	win_popup.visible = false
	win_popup_overlay.visible = false
	$UI/Header/Tabs.visible = true
	_set_tab_active(true)
	_populate_items_ui()

func _on_inventory_tab_pressed() -> void:
	cases_panel.visible = false
	inventory_panel.visible = true
	opener_panel.visible = false
	win_popup.visible = false
	win_popup_overlay.visible = false
	$UI/Header/Tabs.visible = true
	_set_tab_active(false)
	_populate_inventory_ui()

func update_ui() -> void:
	gold_label.text = str(gold) + " G"
	silver_label.text = str(silver) + " S"

# --- SUBTAB SWITCHING ---

func _on_boxes_subtab_pressed() -> void:
	showing_boxes = true
	_populate_items_ui()

func _on_cases_subtab_pressed() -> void:
	showing_boxes = false
	_populate_items_ui()

func _populate_items_ui() -> void:
	var boxes_grid = $UI/MainArea/CasesPanel/VBox/BoxesGrid
	var cases_grid = $UI/MainArea/CasesPanel/VBox/CasesGrid
	var boxes_btn = $UI/MainArea/CasesPanel/VBox/SubTabs/BoxesBtn
	var cases_btn = $UI/MainArea/CasesPanel/VBox/SubTabs/CasesBtn

	boxes_grid.visible = showing_boxes
	cases_grid.visible = not showing_boxes

	boxes_btn.add_theme_color_override("font_color", Color.ORANGE if showing_boxes else Color.WHITE)
	cases_btn.add_theme_color_override("font_color", Color.ORANGE if not showing_boxes else Color.WHITE)

	if showing_boxes:
		_populate_grid(boxes_grid, SkinData.BOXES, true)
	else:
		_populate_grid(cases_grid, SkinData.CASES, false)

func _populate_grid(grid: HBoxContainer, items: Dictionary, is_box: bool) -> void:
	for child in grid.get_children():
		child.queue_free()

	for item_name in items.keys():
		var item_info = items[item_name]
		var price = item_info["price"]
		var skins = item_info["skins"]
		var weights = item_info["rarity_weights"]

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(280, 350)

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.16, 0.2, 1)
		style.corner_radius_top_left = 18
		style.corner_radius_top_right = 18
		style.corner_radius_bottom_left = 18
		style.corner_radius_bottom_right = 18
		card.add_theme_stylebox_override("panel", style)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 15)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(vbox)

		var icon_area = ColorRect.new()
		icon_area.custom_minimum_size = Vector2(240, 200)
		icon_area.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_area.color = Color(0.16, 0.16, 0.2, 1)
		vbox.add_child(icon_area)

		var display_name = item_name.to_upper()
		var icon_label = Label.new()
		icon_label.text = display_name
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_label.add_theme_font_size_override("font_size", 22)
		icon_label.add_theme_color_override("font_color", Color.WHITE)
		icon_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_area.add_child(icon_label)

		var currency = "G" if not is_box else "S"
		var price_label = Label.new()
		price_label.text = "Цена: " + str(price) + " " + currency
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_label.add_theme_font_size_override("font_size", 18)
		price_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.9, 1))
		vbox.add_child(price_label)

		var buy_btn = Button.new()
		buy_btn.text = "Открыть"
		buy_btn.custom_minimum_size = Vector2(200, 42)
		buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		buy_btn.add_theme_font_size_override("font_size", 16)
		var captured_name = item_name
		var captured_is_box = is_box
		buy_btn.pressed.connect(func(): _on_buy_case_pressed(captured_name, captured_is_box))
		vbox.add_child(buy_btn)

		grid.add_child(card)

# --- INVENTORY SYSTEM ---

func _populate_inventory_ui() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()

	if inventory.size() == 0:
		inventory_empty_label.visible = true
		inventory_grid.visible = false
	else:
		inventory_empty_label.visible = false
		inventory_grid.visible = true

		for idx in range(inventory.size()):
			var skin = inventory[idx]
			var rarity_name = skin["rarity"]
			var rarity_color = SkinData.RARITIES[rarity_name]["color"]
			var sell_price = SkinData.RARITIES[rarity_name]["price"]

			var card = PanelContainer.new()
			card.custom_minimum_size = Vector2(160, 200)

			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.12, 0.12, 0.15)
			style.border_width_bottom = 5
			style.border_color = rarity_color
			style.corner_radius_top_left = 6
			style.corner_radius_top_right = 6
			style.corner_radius_bottom_left = 6
			style.corner_radius_bottom_right = 6
			card.add_theme_stylebox_override("panel", style)

			var vbox = VBoxContainer.new()
			vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_theme_constant_override("separation", 10)
			card.add_child(vbox)

			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(0, 10)
			vbox.add_child(spacer)

			var weapon_rect = ColorRect.new()
			weapon_rect.custom_minimum_size = Vector2(100, 60)
			weapon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			weapon_rect.color = rarity_color.lerp(Color.BLACK, 0.4)

			var weapon_text = Label.new()
			weapon_text.text = skin["weapon"]
			weapon_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			weapon_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			weapon_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			weapon_rect.add_child(weapon_text)
			vbox.add_child(weapon_rect)

			var name_label = Label.new()
			name_label.text = skin["skin"]
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.add_theme_font_size_override("font_size", 14)
			vbox.add_child(name_label)

			var rarity_label = Label.new()
			rarity_label.text = rarity_name.to_upper()
			rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rarity_label.add_theme_color_override("font_color", rarity_color)
			rarity_label.add_theme_font_size_override("font_size", 10)
			vbox.add_child(rarity_label)

			var sell_btn = Button.new()
			sell_btn.text = "Sell for " + str(sell_price) + "G"
			sell_btn.custom_minimum_size = Vector2(120, 28)
			sell_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var captured_idx = idx
			sell_btn.pressed.connect(func(): _sell_inventory_item(captured_idx))
			vbox.add_child(sell_btn)

			inventory_grid.add_child(card)

func _sell_inventory_item(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var skin = inventory[index]
	var rarity = skin["rarity"]
	var sell_price = SkinData.RARITIES[rarity]["price"]
	gold += sell_price
	inventory.remove_at(index)
	update_ui()
	_populate_inventory_ui()
	save_game()

# --- CASE OPENER SCREEN ---

func _on_buy_case_pressed(item_name: String, is_box: bool) -> void:
	if is_rolling:
		return

	var items = SkinData.BOXES if is_box else SkinData.CASES
	if not items.has(item_name):
		return

	var case_price = items[item_name]["price"]
	if is_box:
		if silver < case_price:
			silver_label.add_theme_color_override("font_color", Color.RED)
			await get_tree().create_timer(0.5).timeout
			silver_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
			return
		silver -= case_price
	else:
		if gold < case_price:
			gold_label.add_theme_color_override("font_color", Color.RED)
			await get_tree().create_timer(0.5).timeout
			gold_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
			return
		gold -= case_price
	update_ui()
	save_game()

	current_item_name = item_name
	current_is_box = is_box

	cases_panel.visible = false
	inventory_panel.visible = false
	opener_panel.visible = true
	$UI/Header/Tabs.visible = false

	$UI/OpenerPanel/CaseTitle.text = item_name.to_upper()
	$UI/OpenerPanel/BackBtn.disabled = true

	_setup_roll_ui()
	_start_roll()

func _close_opener() -> void:
	if is_rolling:
		return
	_on_cases_tab_pressed()

func _setup_roll_ui() -> void:
	for child in roll_container.get_children():
		child.queue_free()

	roll_container.position.x = 0

	var pointer = $UI/OpenerPanel/RollArea/Pointer
	if pointer:
		pointer.visible = true

	var items = SkinData.BOXES if current_is_box else SkinData.CASES
	if not items.has(current_item_name):
		return
	var sample_skins = items[current_item_name]["skins"]
	for i in range(15):
		var skin = sample_skins[randi() % sample_skins.size()]
		var card = _create_roll_card(skin)
		roll_container.add_child(card)

func _create_roll_card(skin: Dictionary) -> PanelContainer:
	var rarity_name = skin["rarity"]
	var rarity_color = SkinData.RARITIES[rarity_name]["color"]

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(card_width, 120)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13)
	style.border_width_bottom = 4
	style.border_color = rarity_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	card.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)

	var rect = ColorRect.new()
	rect.custom_minimum_size = Vector2(90, 45)
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rect.color = rarity_color.lerp(Color.BLACK, 0.5)

	var rect_lbl = Label.new()
	rect_lbl.text = skin["weapon"]
	rect_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rect_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rect_lbl.add_theme_font_size_override("font_size", 11)
	rect_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.add_child(rect_lbl)

	vbox.add_child(rect)

	var sname = Label.new()
	sname.text = skin["skin"]
	sname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sname.add_theme_font_size_override("font_size", 12)
	vbox.add_child(sname)

	var rtag = Label.new()
	rtag.text = rarity_name.to_upper()
	rtag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rtag.add_theme_color_override("font_color", rarity_color)
	rtag.add_theme_font_size_override("font_size", 8)
	vbox.add_child(rtag)

	card.add_child(vbox)
	return card

# --- ROLLING MECHANIC ---

func _start_roll() -> void:
	if is_rolling:
		return

	is_rolling = true
	$UI/OpenerPanel/SpinBtn.disabled = true
	$UI/OpenerPanel/BackBtn.disabled = true

	winning_skin = SkinData.get_random_skin(current_item_name, current_is_box)

	roll_skins.clear()
	var items = SkinData.BOXES if current_is_box else SkinData.CASES
	if not items.has(current_item_name):
		is_rolling = false
		return
	var case_skins = items[current_item_name]["skins"]

	for child in roll_container.get_children():
		child.queue_free()

	roll_container.position.x = 0

	for i in range(40):
		var skin_to_add: Dictionary
		if i == winning_index:
			skin_to_add = winning_skin
		else:
			skin_to_add = case_skins[randi() % case_skins.size()]
		roll_skins.append(skin_to_add)
		var card = _create_roll_card(skin_to_add)
		roll_container.add_child(card)

	await get_tree().process_frame

	var organic_offset = randf_range(-55.0, 55.0)
	var target_x = 300.0 - ((winning_index * (card_width + card_gap)) + (card_width / 2.0)) + organic_offset

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(roll_container, "position:x", target_x, 4.5)

	await tween.finished
	_show_win_popup()

func _show_win_popup() -> void:
	is_rolling = false

	var pointer = $UI/OpenerPanel/RollArea/Pointer
	if pointer:
		pointer.visible = false

	var rarity = winning_skin["rarity"]
	var rarity_color = SkinData.RARITIES[rarity]["color"]
	var sell_price = SkinData.RARITIES[rarity]["price"]

	win_weapon_label.text = winning_skin["weapon"]
	win_skin_label.text = winning_skin["skin"]
	win_rarity_label.text = rarity.to_upper()
	win_rarity_label.add_theme_color_override("font_color", rarity_color)

	var wp = $UI/WinPopup/VBox/WeaponPanel
	if wp:
		var wp_style = wp.get_theme_stylebox("panel") as StyleBoxFlat
		if wp_style:
			wp_style.border_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.35)

	var price_label = $UI/WinPopup/VBox/PriceLabel
	if price_label:
		price_label.text = "Продажа: " + str(sell_price) + " G"

	win_popup.visible = true
	win_popup_overlay.visible = true

	if win_glow_tween:
		win_glow_tween.kill()
	var card_style = win_popup.get_theme_stylebox("panel") as StyleBoxFlat
	if card_style:
		win_glow_tween = create_tween().set_loops()
		win_glow_tween.tween_property(card_style, "shadow_size", 50, 1.2).from(25)
		win_glow_tween.tween_property(card_style, "shadow_size", 25, 1.2).from(50)
		win_glow_tween.chain()

	$UI/OpenerPanel/SpinBtn.disabled = false
	$UI/OpenerPanel/BackBtn.disabled = false

func _on_claim_pressed() -> void:
	if win_glow_tween:
		win_glow_tween.kill()
	inventory.append(winning_skin)
	win_popup.visible = false
	win_popup_overlay.visible = false
	save_game()
	_on_cases_tab_pressed()

func _on_sell_instantly_pressed() -> void:
	if win_glow_tween:
		win_glow_tween.kill()
	var rarity = winning_skin["rarity"]
	var sell_price = SkinData.RARITIES[rarity]["price"]
	gold += sell_price
	update_ui()
	win_popup.visible = false
	win_popup_overlay.visible = false
	save_game()
	_on_cases_tab_pressed()

# --- AUTH INTEGRATION ---

func _on_profile_pressed() -> void:
	if auth_scene_instance and is_instance_valid(auth_scene_instance):
		auth_scene_instance.queue_free()
		auth_scene_instance = null
		return
	auth_scene_instance = null
	if logged_in_user != "":
		_show_profile_popup()
		return
	_show_auth_scene()

func _show_auth_scene() -> void:
	if auth_scene_instance:
		return
	var auth_scene = load("res://auth_scene.tscn")
	if auth_scene:
		auth_scene_instance = auth_scene.instantiate()
		auth_scene_instance.auth_success.connect(_on_auth_success)
		add_child(auth_scene_instance)

func _on_auth_success(username: String) -> void:
	print("Auth success: ", username)
	logged_in_user = username
	if auth_scene_instance:
		logged_in_id = auth_scene_instance.get_user_id()
		auth_scene_instance.queue_free()
		auth_scene_instance = null
	load_game()
	update_ui()

func _on_auth_failed(reason: String) -> void:
	print("Auth failed: ", reason)

func _show_profile_popup() -> void:
	var existing = get_node_or_null("ProfilePopup")
	if existing:
		existing.queue_free()
		return

	var popup = PanelContainer.new()
	popup.name = "ProfilePopup"
	popup.custom_minimum_size = Vector2(420, 320)
	popup.size = Vector2(420, 320)
	popup.position = (get_viewport_rect().size - popup.custom_minimum_size) / 2 + Vector2(0, -40)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.25, 0.25, 0.32, 0.5)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 30
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	popup.add_theme_stylebox_override("panel", style)
	add_child(popup)
	popup.z_index = 100

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)

	var title = Label.new()
	title.text = "Профиль"
	title.horizontal_alignment = 1
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer1)

	var avatar_container = CenterContainer.new()
	vbox.add_child(avatar_container)

	var avatar_tex = ImageTexture.new()
	var avatar_img = null
	if ResourceLoader.exists("res://assets/GGGGGGGGGGGGG.jpg"):
		avatar_img = load("res://assets/GGGGGGGGGGGGG.jpg")
	elif ResourceLoader.exists("res://assets/avatar.jpg"):
		avatar_img = load("res://assets/avatar.jpg")
	elif ResourceLoader.exists("res://assets/avatar.png"):
		avatar_img = load("res://assets/avatar.png")

	if avatar_img:
		var tex_rect = TextureRect.new()
		tex_rect.texture = avatar_img
		tex_rect.custom_minimum_size = Vector2(90, 90)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		var avatar_clip = PanelContainer.new()
		avatar_clip.custom_minimum_size = Vector2(90, 90)
		var clip_style = StyleBoxFlat.new()
		clip_style.bg_color = Color(0.15, 0.15, 0.2, 1)
		clip_style.corner_radius_top_left = 20
		clip_style.corner_radius_top_right = 20
		clip_style.corner_radius_bottom_left = 20
		clip_style.corner_radius_bottom_right = 20
		clip_style.border_width_left = 2
		clip_style.border_width_top = 2
		clip_style.border_width_right = 2
		clip_style.border_width_bottom = 2
		clip_style.border_color = Color(0.5, 0.4, 0.1, 0.6)
		avatar_clip.add_theme_stylebox_override("panel", clip_style)
		avatar_clip.add_child(tex_rect)
		avatar_container.add_child(avatar_clip)
	else:
		var avatar = PanelContainer.new()
		avatar.custom_minimum_size = Vector2(90, 90)
		var avatar_style = StyleBoxFlat.new()
		avatar_style.bg_color = Color(0.15, 0.12, 0.06, 1)
		avatar_style.corner_radius_top_left = 20
		avatar_style.corner_radius_top_right = 20
		avatar_style.corner_radius_bottom_left = 20
		avatar_style.corner_radius_bottom_right = 20
		avatar_style.border_width_left = 2
		avatar_style.border_width_top = 2
		avatar_style.border_width_right = 2
		avatar_style.border_width_bottom = 2
		avatar_style.border_color = Color(0.55, 0.45, 0.10, 0.4)
		avatar.add_theme_stylebox_override("panel", avatar_style)
		avatar_container.add_child(avatar)
		var avatar_label = Label.new()
		avatar_label.text = logged_in_user.left(1).to_upper()
		avatar_label.horizontal_alignment = 1
		avatar_label.vertical_alignment = 1
		avatar_label.add_theme_font_size_override("font_size", 36)
		avatar_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
		avatar.add_child(avatar_label)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer2)

	var nick_label = Label.new()
	nick_label.text = logged_in_user
	nick_label.horizontal_alignment = 1
	nick_label.add_theme_font_size_override("font_size", 20)
	nick_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(nick_label)

	var id_label = Label.new()
	id_label.text = "ID: " + logged_in_id
	id_label.horizontal_alignment = 1
	id_label.add_theme_font_size_override("font_size", 15)
	id_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	vbox.add_child(id_label)

	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer3)

	var separator = HSeparator.new()
	separator.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(separator)

	var promo_title = Label.new()
	promo_title.text = "Промокод"
	promo_title.horizontal_alignment = 1
	promo_title.add_theme_font_size_override("font_size", 16)
	promo_title.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	vbox.add_child(promo_title)

	var promo_row = HBoxContainer.new()
	promo_row.add_theme_constant_override("separation", 8)
	vbox.add_child(promo_row)

	var promo_input = LineEdit.new()
	promo_input.placeholder_text = "Введите код..."
	promo_input.custom_minimum_size = Vector2(200, 40)
	promo_input.size_flags_horizontal = 3
	promo_input.max_length = 30
	promo_input.character_spaces_only = true
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.14, 0.14, 0.18, 1)
	input_style.border_width_left = 1
	input_style.border_width_top = 1
	input_style.border_width_right = 1
	input_style.border_width_bottom = 1
	input_style.border_color = Color(0.3, 0.3, 0.38, 1)
	input_style.corner_radius_top_left = 8
	input_style.corner_radius_top_right = 8
	input_style.corner_radius_bottom_left = 8
	input_style.corner_radius_bottom_right = 8
	input_style.content_margin_left = 10
	input_style.content_margin_right = 10
	promo_input.add_theme_stylebox_override("normal", input_style)
	promo_input.add_theme_color_override("font_color", Color.WHITE)
	promo_input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.5))
	promo_row.add_child(promo_input)

	var promo_btn = Button.new()
	promo_btn.text = "Активировать"
	promo_btn.custom_minimum_size = Vector2(130, 40)
	promo_btn.add_theme_font_size_override("font_size", 14)
	var promo_btn_style = StyleBoxFlat.new()
	promo_btn_style.bg_color = Color(0.25, 0.55, 0.25, 1)
	promo_btn_style.corner_radius_top_left = 8
	promo_btn_style.corner_radius_top_right = 8
	promo_btn_style.corner_radius_bottom_left = 8
	promo_btn_style.corner_radius_bottom_right = 8
	promo_btn_style.content_margin_left = 14
	promo_btn_style.content_margin_right = 14
	promo_btn_style.content_margin_top = 8
	promo_btn_style.content_margin_bottom = 8
	promo_btn.add_theme_stylebox_override("normal", promo_btn_style)
	var promo_btn_hover = promo_btn_style.duplicate()
	promo_btn_hover.bg_color = Color(0.32, 0.65, 0.32, 1)
	promo_btn.add_theme_stylebox_override("hover", promo_btn_hover)
	promo_btn.add_theme_color_override("font_color", Color.WHITE)
	promo_row.add_child(promo_btn)

	var promo_result = Label.new()
	promo_result.text = ""
	promo_result.horizontal_alignment = 1
	promo_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	promo_result.add_theme_font_size_override("font_size", 13)
	vbox.add_child(promo_result)

	var close_btn = Button.new()
	close_btn.text = "Закрыть"
	close_btn.custom_minimum_size = Vector2(200, 44)
	close_btn.size_flags_horizontal = 1
	close_btn.add_theme_font_size_override("font_size", 16)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.20, 0.20, 0.26, 1)
	btn_style.border_width_left = 1
	btn_style.border_width_top = 1
	btn_style.border_width_right = 1
	btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.35, 0.35, 0.42, 1)
	btn_style.corner_radius_top_left = 10
	btn_style.corner_radius_top_right = 10
	btn_style.corner_radius_bottom_left = 10
	btn_style.corner_radius_bottom_right = 10
	btn_style.content_margin_left = 24
	btn_style.content_margin_right = 24
	btn_style.content_margin_top = 12
	btn_style.content_margin_bottom = 12
	close_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.28, 0.28, 0.35, 1)
	btn_hover.border_color = Color(0.45, 0.45, 0.52, 1)
	close_btn.add_theme_stylebox_override("hover", btn_hover)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(close_btn)

	promo_btn.pressed.connect(func():
		var code = promo_input.text.strip_edges()
		if code.is_empty():
			promo_result.text = "Введите промокод"
			promo_result.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			return
		promo_btn.disabled = true
		promo_result.text = "Проверка..."
		promo_result.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		_redeem_promo(code, promo_result, promo_btn)
	)

	close_btn.pressed.connect(func(): popup.queue_free())

func _redeem_promo(code: String, result_label: Label, btn: Button) -> void:
	if logged_in_user.is_empty():
		result_label.text = "Нужна авторизация"
		result_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		btn.disabled = false
		return

	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, response_code, _headers, body):
		http.queue_free()
		btn.disabled = false
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			var err_data = JSON.new()
			if err_data.parse(body.get_string_from_utf8()) == OK and err_data.data.has("error"):
				result_label.text = err_data.data["error"]
			else:
				result_label.text = "Ошибка сервера"
			result_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			return
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.data
			var reward_type = data.get("reward_type", "silver")
			var amount = int(data.get("amount", 0))
			if reward_type == "gold":
				gold += amount
			else:
				silver += amount
			save_game()
			update_ui()
			result_label.text = "+" + str(amount) + (" G" if reward_type == "gold" else " S") + " — " + data.get("description", "")
			result_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	)

	var url = SERVER_URL + "/promo/redeem"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"login": logged_in_user, "code": code})
	http.request(url, headers, HTTPClient.METHOD_POST, body)
