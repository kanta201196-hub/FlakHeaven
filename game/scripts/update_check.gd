class_name UpdateCheck
extends Node
## Tells testers about a newer build (Kanta 2026-10-25): once per launch fetches
## `site/version.json` from flakheaven.com and compares its build with `Main.BUILD`.
## When the site has a newer one, the main menu shows a card that opens the download page.
## Silent on any failure; off in autotests and screenshot runs.

const URL := "https://flakheaven.com/version.json"

## Newer build from the site ("" — none or unknown) and its download page
static var latest := ""
static var page := ""

var _http: HTTPRequest


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--newbuild="):   # debug: show the card without the site (menu screenshot)
			latest = a.substr(11)
			page = "https://kanta2011.itch.io/flak-heaven"
			return
	if args.has("--autotest") or args.has("--shots") or args.has("--visual") or Demo.on:
		return
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	_http.request_completed.connect(_on_done)
	add_child(_http)
	if _http.request(URL) != OK:
		_http.queue_free()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary):
		return
	var b := String(d.get("build", ""))
	var u := String(d.get("url", ""))
	if BuildOrder.newer(b, Main.BUILD) and u.begins_with("https://"):
		latest = b
		page = u
