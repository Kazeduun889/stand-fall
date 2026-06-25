from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os
import traceback

ADMIN_KEY = "STANDOFF_ADMIN_2026"
MONGO_URI = os.environ.get("MONGO_URI", "")
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")

client = None
db = None
use_mongo = False

os.makedirs(DATA_DIR, exist_ok=True)

def _load_json(name, default=None):
    path = os.path.join(DATA_DIR, f"{name}.json")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return default if default is not None else {}

def _save_json(name, data):
    path = os.path.join(DATA_DIR, f"{name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def get_db():
    global client, db, use_mongo
    if db is not None:
        return db
    if not MONGO_URI:
        return None
    try:
        import certifi
        import pymongo
        from pymongo import MongoClient
        client = MongoClient(
            MONGO_URI,
            tls=True,
            tlsCAFile=certifi.where(),
            serverSelectionTimeoutMS=5000,
            connectTimeoutMS=5000,
            socketTimeoutMS=5000,
        )
        client.admin.command("ping")
        db = client["casenova"]
        use_mongo = True
        return db
    except Exception as e:
        print(f"[WARN] MongoDB connection failed: {e}")
        traceback.print_exc()
        client = None
        db = None
        use_mongo = False
        return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _send(self, code, data):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = self.path.strip("/")

        if path.startswith("user/"):
            login = path[5:]
            database = get_db()
            if database is not None:
                user = database.users.find_one({"login": login}, {"_id": 0})
                if user:
                    self._send(200, user)
                else:
                    self._send(404, {"error": "not found"})
            else:
                users = _load_json("users", {})
                if login in users:
                    self._send(200, users[login])
                else:
                    self._send(404, {"error": "not found"})

        elif path == "health":
            self._send(200, {"status": "ok", "mongo": use_mongo})

        elif path == "stats":
            database = get_db()
            if database is not None:
                count = database.users.count_documents({})
                counter = database.counters.find_one({"_id": "next_id"})
                next_id = counter["value"] if counter else 1000000
                self._send(200, {"total_users": count, "next_id": next_id})
            else:
                users = _load_json("users", {})
                counters = _load_json("counters", {"next_id": 1000000})
                self._send(200, {"total_users": len(users), "next_id": counters.get("next_id", 1000000)})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.strip("/")
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length)) if length else {}

        if path == "admin/set_id":
            key = body.get("key", "")
            login = body.get("login", "")
            new_id = body.get("user_id", 0)
            if key != ADMIN_KEY:
                self._send(403, {"error": "wrong admin key"})
                return
            if not login or not new_id:
                self._send(400, {"error": "login and user_id required"})
                return
            database = get_db()
            if database is not None:
                user = database.users.find_one({"login": login})
                if not user:
                    self._send(404, {"error": "user not found"})
                    return
                database.users.update_one({"login": login}, {"$set": {"user_id": int(new_id)}})
                self._send(200, {"status": "ok", "login": login, "user_id": int(new_id)})
            else:
                users = _load_json("users", {})
                if login not in users:
                    self._send(404, {"error": "user not found"})
                    return
                users[login]["user_id"] = int(new_id)
                _save_json("users", users)
                self._send(200, {"status": "ok", "login": login, "user_id": int(new_id)})
            return

        if path == "admin/users":
            key = body.get("key", "")
            if key != ADMIN_KEY:
                self._send(403, {"error": "wrong admin key"})
                return
            database = get_db()
            if database is not None:
                users = {}
                for u in database.users.find({}, {"_id": 0}):
                    login = u.get("login", "")
                    users[login] = {"user_id": u.get("user_id", 0), "password": u.get("password", "")}
                counter = database.counters.find_one({"_id": "next_id"})
                next_id = counter["value"] if counter else 1000000
                self._send(200, {"users": users, "next_id": next_id})
            else:
                users = _load_json("users", {})
                counters = _load_json("counters", {"next_id": 1000000})
                out = {}
                for login, u in users.items():
                    out[login] = {"user_id": u.get("user_id", 0), "password": u.get("password", "")}
                self._send(200, {"users": out, "next_id": counters.get("next_id", 1000000)})
            return

        if path == "admin/backup":
            key = body.get("key", "")
            if key != ADMIN_KEY:
                self._send(403, {"error": "wrong admin key"})
                return
            database = get_db()
            if database is not None:
                users_list = list(database.users.find({}, {"_id": 0}))
                promos_doc = database.promos.find_one({"_id": "main"}, {"_id": 0})
                counter = database.counters.find_one({"_id": "next_id"})
                next_id = counter["value"] if counter else 1000000
                self._send(200, {"users": users_list, "next_id": next_id, "promos": promos_doc or {}})
            else:
                users = _load_json("users", {})
                counters = _load_json("counters", {"next_id": 1000000})
                promos = _load_json("promos", {})
                users_list = [{"login": k, **v} for k, v in users.items()]
                self._send(200, {"users": users_list, "next_id": counters.get("next_id", 1000000), "promos": promos})
            return

        if path == "admin/restore":
            key = body.get("key", "")
            if key != ADMIN_KEY:
                self._send(403, {"error": "wrong admin key"})
                return
            database = get_db()
            if database is not None:
                if "users" in body:
                    database.users.drop()
                    for u in body["users"]:
                        database.users.insert_one(u)
                if "next_id" in body:
                    database.counters.update_one({"_id": "next_id"}, {"$set": {"value": body["next_id"]}}, upsert=True)
                if "promos" in body:
                    database.promos.update_one({"_id": "main"}, {"$set": body["promos"]}, upsert=True)
                self._send(200, {"status": "ok", "message": "database restored"})
            else:
                if "users" in body:
                    users = {}
                    for u in body["users"]:
                        login = u.get("login", "")
                        users[login] = u
                    _save_json("users", users)
                if "next_id" in body:
                    _save_json("counters", {"next_id": body["next_id"]})
                if "promos" in body:
                    _save_json("promos", body["promos"])
                self._send(200, {"status": "ok", "message": "database restored (file)"})
            return

        if path == "reset":
            database = get_db()
            if database is not None:
                database.users.drop()
                database.promos.drop()
                database.counters.update_one({"_id": "next_id"}, {"$set": {"value": 1000000}}, upsert=True)
            else:
                _save_json("users", {})
                _save_json("counters", {"next_id": 1000000})
                _save_json("promos", {})
            self._send(200, {"status": "ok", "message": "database reset"})
            return

        if path == "promo/redeem":
            login = body.get("login", "")
            code = body.get("code", "").upper().strip()
            if not login or not code:
                self._send(400, {"error": "login and code required"})
                return
            database = get_db()
            if database is not None:
                promos_doc = database.promos.find_one({"_id": "main"}) or {}
                codes = promos_doc.get("CODES", {})
                used = promos_doc.get("used", {})
                if code not in codes:
                    self._send(400, {"error": "Промокод не найден"})
                    return
                if login not in used:
                    used[login] = []
                if code in used[login]:
                    self._send(400, {"error": "Вы уже использовали этот промокод"})
                    return
                reward = codes[code]
                used[login].append(code)
                database.promos.update_one({"_id": "main"}, {"$set": {"used": used}}, upsert=True)
                self._send(200, {"status": "ok", "reward_type": reward.get("type", "silver"), "amount": reward.get("amount", 0), "description": reward.get("description", "")})
            else:
                promos = _load_json("promos", {})
                codes = promos.get("CODES", {})
                used = promos.get("used", {})
                if code not in codes:
                    self._send(400, {"error": "Промокод не найден"})
                    return
                if login not in used:
                    used[login] = []
                if code in used[login]:
                    self._send(400, {"error": "Вы уже использовали этот промокод"})
                    return
                reward = codes[code]
                used[login].append(code)
                promos["used"] = used
                _save_json("promos", promos)
                self._send(200, {"status": "ok", "reward_type": reward.get("type", "silver"), "amount": reward.get("amount", 0), "description": reward.get("description", "")})
            return

        if path == "promo/check":
            login = body.get("login", "")
            code = body.get("code", "").upper().strip()
            database = get_db()
            if database is not None:
                promos_doc = database.promos.find_one({"_id": "main"}) or {}
                codes = promos_doc.get("CODES", {})
                used = promos_doc.get("used", {})
            else:
                promos = _load_json("promos", {})
                codes = promos.get("CODES", {})
                used = promos.get("used", {})
            if code not in codes:
                self._send(400, {"error": "Промокод не найден"})
                return
            if login in used and code in used[login]:
                self._send(400, {"error": "Уже использован"})
                return
            reward = codes[code]
            self._send(200, {"status": "ok", "description": reward.get("description", ""), "type": reward.get("type", ""), "amount": reward.get("amount", 0)})
            return

        if path == "register":
            login = body.get("login", "")
            password = body.get("password", "")
            if not login:
                self._send(400, {"error": "login required"})
                return
            database = get_db()
            if database is not None:
                existing = database.users.find_one({"login": login})
                if existing:
                    if password and "password" not in existing:
                        database.users.update_one({"login": login}, {"$set": {"password": password}})
                        existing["password"] = password
                    self._send(200, existing)
                    return
                counter = database.counters.find_one({"_id": "next_id"})
                user_id = counter["value"] if counter else 1000000
                database.counters.update_one({"_id": "next_id"}, {"$set": {"value": user_id + 1}}, upsert=True)
                new_user = {"user_id": user_id, "login": login, "password": password}
                database.users.insert_one(new_user)
                self._send(200, {"user_id": user_id, "login": login})
            else:
                users = _load_json("users", {})
                counters = _load_json("counters", {"next_id": 1000000})
                if login in users:
                    if password and "password" not in users[login]:
                        users[login]["password"] = password
                        _save_json("users", users)
                    self._send(200, users[login])
                    return
                user_id = counters.get("next_id", 1000000)
                counters["next_id"] = user_id + 1
                _save_json("counters", counters)
                users[login] = {"user_id": user_id, "login": login, "password": password}
                _save_json("users", users)
                self._send(200, {"user_id": user_id, "login": login})
            return

        if path.startswith("get_id/"):
            login = path[7:]
            database = get_db()
            if database is not None:
                user = database.users.find_one({"login": login}, {"_id": 0})
                if user:
                    self._send(200, user)
                else:
                    self._send(404, {"error": "not found"})
            else:
                users = _load_json("users", {})
                if login in users:
                    self._send(200, users[login])
                else:
                    self._send(404, {"error": "not found"})
            return

        if path == "health":
            self._send(200, {"status": "ok", "mongo": use_mongo})
            return

        self._send(404, {"error": "not found"})


PORT = int(os.environ.get("PORT", 10000))
server = HTTPServer(("0.0.0.0", PORT), Handler)
print(f"Server running on port {PORT} (mongo={MONGO_URI != ''})")
server.serve_forever()
