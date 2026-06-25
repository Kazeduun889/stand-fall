extends Control

signal auth_success(username: String)

const SAVE_PATH = "user://auth_data.json"
const PROFILES_PATH = "user://profiles.json"
const MAX_ACCOUNTS = 3
const SERVER_URL = "https://stand-fall.onrender.com"

var current_user: String = ""
var users_db: Dictionary = {}
var http_request: HTTPRequest

var login_input: LineEdit
var password_input: LineEdit
var error_label: Label
var action_btn: Button
var close_btn: Button

var _pending_login: String = ""
var _pending_password: String = ""

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_completed)
	load_users_db()
	_find_nodes()
	_connect_ui()

func _find_nodes() -> void:
	login_input = _find(self, "LoginInput")
	password_input = _find(self, "PasswordInput")
	error_label = _find(self, "ErrorLabel")
	action_btn = _find(self, "ActionBtn")
	close_btn = _find(self, "CloseBtn")
	if error_label:
		error_label.visible = false

func _find(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found = _find(child, target_name)
		if found:
			return found
	return null

func _connect_ui() -> void:
	if action_btn:
		action_btn.pressed.connect(_on_action_pressed)
	if close_btn:
		close_btn.pressed.connect(_on_close_pressed)
	if password_input:
		password_input.text_submitted.connect(func(_t): _on_action_pressed())

func load_users_db() -> void:
	if FileAccess.file_exists(PROFILES_PATH):
		var file = FileAccess.open(PROFILES_PATH, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(text) == OK:
				users_db = json.data if json.data is Dictionary else {}

func save_users_db() -> void:
	var file = FileAccess.open(PROFILES_PATH, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(users_db))
		file.close()

func get_user_id() -> String:
	if current_user and users_db.has(current_user) and "user_id" in users_db[current_user]:
		return str(int(users_db[current_user]["user_id"]))
	return ""

func save_session() -> void:
	pass

func load_session() -> void:
	pass

func get_username() -> String:
	if current_user and users_db.has(current_user):
		return users_db[current_user]["username"]
	return "Гость"

func get_account_count() -> int:
	return users_db.size()

func _on_action_pressed() -> void:
	if not login_input or not password_input:
		return
	var login = login_input.text.strip_edges()
	var password = password_input.text

	if login.is_empty() or password.is_empty():
		_show_error("Заполните все поля")
		return

	if login.length() < 3:
		_show_error("Логин минимум 3 символа")
		return

	if password.length() < 4:
		_show_error("Пароль минимум 4 символа")
		return

	if users_db.has(login):
		if users_db[login]["password"] == password:
			_clear_error()
			current_user = login
			save_session()
			_clear_fields()
			emit_signal("auth_success", login)
			_fetch_global_id_async(login)
			return
		else:
			_show_error("Неверный пароль")
		return

	if get_account_count() >= MAX_ACCOUNTS:
		_show_error("Максимум " + str(MAX_ACCOUNTS) + " аккаунтов")
		return

	_pending_login = login
	_pending_password = password
	_register_on_server(login)

func _register_on_server(login: String) -> void:
	var url = SERVER_URL + "/register"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"login": login, "password": _pending_password})
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		_finish_registration(login, _pending_password, _get_local_next_id())

func _fetch_global_id_async(login: String) -> void:
	var url = SERVER_URL + "/register"
	var headers = ["Content-Type: application/json"]
	var password = ""
	if users_db.has(login):
		password = users_db[login].get("password", "")
	var body = JSON.stringify({"login": login, "password": password})
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		pass

func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if _pending_login != "":
			_finish_registration(_pending_login, _pending_password, _get_local_next_id())
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		if _pending_login != "":
			_finish_registration(_pending_login, _pending_password, _get_local_next_id())
		return

	var data = json.data
	if data.has("user_id"):
		var global_id = int(data["user_id"])
		if _pending_login != "":
			_finish_registration(_pending_login, _pending_password, global_id)
		elif current_user != "" and users_db.has(current_user):
			users_db[current_user]["user_id"] = global_id
			save_users_db()

func _finish_registration(login: String, password: String, user_id: int) -> void:
	users_db[login] = {"password": password, "username": login, "user_id": user_id}
	save_users_db()
	_clear_error()
	current_user = login
	save_session()
	_clear_fields()
	_pending_login = ""
	_pending_password = ""
	emit_signal("auth_success", login)

func _get_local_next_id() -> int:
	var max_id := 1000000 - 1
	for login in users_db:
		if "user_id" in users_db[login]:
			var uid = int(users_db[login]["user_id"])
			if uid > max_id:
				max_id = uid
	return max_id + 1

func _on_close_pressed() -> void:
	queue_free()

func _show_error(msg: String) -> void:
	if error_label:
		error_label.text = msg
		error_label.visible = true

func _clear_error() -> void:
	if error_label:
		error_label.visible = false

func _clear_fields() -> void:
	if login_input:
		login_input.text = ""
	if password_input:
		password_input.text = ""
