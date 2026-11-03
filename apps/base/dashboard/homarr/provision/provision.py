"""Bootstrap Homarr and keep the "homelab" board in step with board.json.

Homarr keeps boards and apps in its database and has no file-based import, so
this drives its tRPC API instead. On a fresh install it does the onboarding
that would otherwise be clicked through at /init (claim, first admin, setup),
then on every run it upserts the apps in board.json and rewrites the board's
whole content. Edits made to that board in the UI are overwritten on the next
sync; other boards and apps are left alone.

Stdlib only, so it runs on a stock python image.
"""

import hashlib
import json
import math
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("HOMARR_URL", "http://homarr:7575").rstrip("/")
USERNAME = os.environ["HOMARR_USERNAME"]
PASSWORD = os.environ["HOMARR_PASSWORD"]
BOARD_FILE = os.environ.get("BOARD_FILE", "/provision/board.json")
ICON_BASE = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


opener = urllib.request.build_opener(NoRedirect)
# Cookies are tracked by hand: with an https BASE_URL Homarr marks its session
# cookie Secure, and http.cookiejar would then refuse to send it to the plain
# http Service URL.
cookies = {}


class TrpcError(Exception):
    def __init__(self, code, message):
        super().__init__(f"{code}: {message}")
        self.code = code


def request(method, path, body=None, form=None):
    headers = {}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["content-type"] = "application/json"
    elif form is not None:
        data = urllib.parse.urlencode(form).encode()
        headers["content-type"] = "application/x-www-form-urlencoded"
    if cookies:
        headers["cookie"] = "; ".join(f"{k}={v}" for k, v in cookies.items())
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        resp = opener.open(req, timeout=30)
    except urllib.error.HTTPError as err:
        resp = err
    for header in resp.headers.get_all("set-cookie") or []:
        name, _, rest = header.partition("=")
        value = rest.split(";", 1)[0]
        if value:
            cookies[name.strip()] = value
        else:
            cookies.pop(name.strip(), None)
    raw = resp.read()
    try:
        payload = json.loads(raw) if raw else None
    except ValueError:
        payload = None
    return resp.status, payload


def trpc(procedure, value=None, mutation=False):
    if mutation:
        status, payload = request("POST", f"/api/trpc/{procedure}", body={"json": value})
    else:
        query = ""
        if value is not None:
            query = "?input=" + urllib.parse.quote(json.dumps({"json": value}))
        status, payload = request("GET", f"/api/trpc/{procedure}{query}")
    if payload and "error" in payload:
        err = payload["error"]["json"]
        raise TrpcError(err.get("data", {}).get("code", status), err.get("message"))
    if status >= 400 or not payload:
        raise TrpcError(status, f"{procedure} returned HTTP {status}")
    return payload["result"]["data"].get("json")


def mutate(procedure, value=None):
    return trpc(procedure, value, mutation=True)


def stable_id(*parts):
    # Deterministic IDs keep the board's items and sections the same across runs.
    return hashlib.sha1(":".join(("homelab-provision",) + parts).encode()).hexdigest()[:24]


def wait_until_ready():
    for _ in range(60):
        try:
            if request("GET", "/api/health/ready")[0] == 200:
                return
        except OSError:
            pass
        time.sleep(5)
    sys.exit("Homarr did not become ready")


def claim_onboarding():
    status, payload = request("POST", "/api/onboarding/claim")
    if status != 200:
        sys.exit(f"Could not claim onboarding: HTTP {status} {payload}")


def sign_in():
    _, payload = request("GET", "/api/auth/csrf")
    status, _ = request(
        "POST",
        "/api/auth/callback/credentials",
        form={"csrfToken": payload["csrfToken"], "name": USERNAME, "password": PASSWORD},
    )
    _, session = request("GET", "/api/auth/session")
    if not session or "admin" not in session.get("user", {}).get("permissions", []):
        sys.exit(f"Sign-in as {USERNAME} failed (HTTP {status}); check the homarr 1Password item")


def onboard(board):
    """Run first-time onboarding. Returns True if it set the instance up."""
    step = trpc("onboard.currentStep")["current"]
    if step == "finish":
        return False
    print(f"Onboarding from step {step!r}")
    if step == "start":
        claim_onboarding()
        mutate("onboard.nextStep")
        step = "user"
    if step == "user":
        claim_onboarding()
        mutate("user.initUser", {"username": USERNAME, "password": PASSWORD, "confirmPassword": PASSWORD})
    sign_in()
    step = trpc("onboard.currentStep")["current"]
    if step == "group":
        sys.exit("Onboarding is waiting on an SSO admin group; finish it in the UI")
    if step == "setup":
        mutate(
            "onboard.completeSetup",
            {
                "server": {"defaultLocale": "en-gb", "defaultColorScheme": "dark"},
                "board": {key: board[key] for key in ("name", "primaryColor", "secondaryColor", "itemRadius")},
            },
        )
        # Onboarding seeds a few links to Homarr's own docs and GitHub; on a
        # fresh install they are the only apps, so clear them out.
        for app in trpc("app.all"):
            mutate("app.delete", {"id": app["id"]})
    return True


def upsert_apps(sections):
    existing = {app["name"]: app for app in trpc("app.all")}
    ids = {}
    for section in sections:
        for app in section["apps"]:
            wanted = {
                "name": app["name"],
                "description": app.get("description") or "",
                "iconUrl": app.get("iconUrl") or f"{ICON_BASE}/{app['icon']}.svg",
                "href": app["href"],
                "pingUrl": app.get("pingUrl") or "",
            }
            current = existing.get(app["name"])
            if current is None:
                ids[app["name"]] = mutate("app.create", wanted)["id"]
                print(f"Created app {app['name']}")
                continue
            ids[app["name"]] = current["id"]
            if any((current.get(key) or "") != value for key, value in wanted.items()):
                mutate("app.update", {"id": current["id"], **wanted})
                print(f"Updated app {app['name']}")
    return ids


def get_board(board):
    try:
        return trpc("board.getBoardByName", {"name": board["name"]})
    except TrpcError as err:
        if err.code != "NOT_FOUND":
            raise
    # Onboarding was done by hand with a different board name.
    mutate("board.createBoard", {"name": board["name"], "columnCount": 10, "isPublic": False})
    return trpc("board.getBoardByName", {"name": board["name"]})


def build_content(definition, layouts, root_id, app_ids):
    items = {}
    sections = []

    def item(item_id, kind, options):
        return items.setdefault(
            item_id,
            {
                "id": item_id,
                "kind": kind,
                "options": options,
                "layouts": [],
                "integrationIds": [],
                "advancedOptions": {"title": None, "customCssClasses": [], "borderColor": ""},
            },
        )

    section_defs = [(stable_id("section", s["title"]), s) for s in definition["sections"]]
    for section_id, section in section_defs:
        sections.append(
            {
                "id": section_id,
                "kind": "container",
                "options": {"title": section["title"], "showLabel": True, "collapsible": True},
                "collapsed": False,
                "layouts": [],
            }
        )

    for layout in layouts:
        columns = layout["columnCount"]
        x = y = row_height = 0
        # Widgets flow left to right across the top of the root section.
        for index, widget in enumerate(definition["widgets"]):
            width = min(widget["width"], columns)
            if x + width > columns:
                x, y, row_height = 0, y + row_height, 0
            item(stable_id("widget", str(index), widget["kind"]), widget["kind"], widget["options"])["layouts"].append(
                {"layoutId": layout["id"], "xOffset": x, "yOffset": y, "width": width, "height": widget["height"], "sectionId": root_id}
            )
            x += width
            row_height = max(row_height, widget["height"])
        y += row_height

        # Then one full-width container per section, apps as 1x1 tiles inside.
        for (section_id, section), out in zip(section_defs, sections):
            rows = max(1, math.ceil(len(section["apps"]) / columns))
            out["layouts"].append(
                {"layoutId": layout["id"], "xOffset": 0, "yOffset": y, "width": columns, "height": rows, "parentSectionId": root_id}
            )
            for index, app in enumerate(section["apps"]):
                options = {
                    "appId": app_ids[app["name"]],
                    "openIn": "newTab",
                    "showTitle": True,
                    "pingEnabled": bool(app.get("pingUrl")),
                    "descriptionDisplayMode": "tooltip",
                }
                item(stable_id("app", app["name"]), "app", options)["layouts"].append(
                    {"layoutId": layout["id"], "xOffset": index % columns, "yOffset": index // columns, "width": 1, "height": 1, "sectionId": section_id}
                )
            y += rows

    root = {"id": root_id, "kind": "empty", "xOffset": 0, "yOffset": 0}
    return [root] + sections, list(items.values())


def main():
    with open(BOARD_FILE) as f:
        definition = json.load(f)
    board_def = definition["board"]

    wait_until_ready()
    if not onboard(board_def):
        sign_in()

    app_ids = upsert_apps(definition["sections"])
    board = get_board(board_def)
    root_id = next(s["id"] for s in board["sections"] if s["kind"] == "empty")
    sections, items = build_content(definition, board["layouts"], root_id, app_ids)
    mutate("board.saveBoard", {"id": board["id"], "sections": sections, "items": items})
    mutate(
        "board.savePartialBoardSettings",
        {"id": board["id"], **{key: board_def[key] for key in ("pageTitle", "primaryColor", "secondaryColor", "itemRadius")}},
    )
    mutate("board.setHomeBoard", {"id": board["id"]})
    mutate("board.setMobileHomeBoard", {"id": board["id"]})
    print(f"Board {board_def['name']!r} saved with {len(items)} items")


if __name__ == "__main__":
    main()
