"""Builds the Lab page's data file (schemaVersion 3, version 2 plus optional newer stats) from QuestPaceLog's saved data.

Reads every QuestPaceLog*.lua under each character's SavedVariables folder,
the live file and the dated backups, and merges their sessions by start
time, so sessions a backup kept but the beta's save bug wiped still count.
Only reads the WTF folder, never writes to it.

    python tools/export_site.py --out path/to/questpacelog.json [--until 2026-09-27]
"""
import argparse, collections, datetime, glob, json, os, re, sys

WTF = r"F:\World of Warcraft\_classic_beta_\WTF\Account"


# --- Reading the Lua file WoW writes -------------------------------------

TOKEN = re.compile(r'\s+|--[^\n]*|"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|[A-Za-z_]\w*|[{}\[\]=,;]')


def tokens(text):
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError("can't read the saved file near: " + text[pos:pos + 40])
        pos = m.end()
        t = m.group()
        if not t.strip() or t.startswith("--"):
            continue
        yield t


def lua_string(t):
    body = t[1:-1]
    return re.sub(r'\\(\d{1,3}|.)', lambda m: chr(int(m.group(1))) if m.group(1).isdigit()
                  else {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), body)


def parse_value(toks, i):
    t = toks[i]
    if t == "{":
        return parse_table(toks, i + 1)
    if t.startswith('"'):
        return lua_string(t), i + 1
    if t in ("true", "false"):
        return t == "true", i + 1
    if t == "nil":
        return None, i + 1
    n = float(t)
    return (int(n) if n.is_integer() and "." not in t and "e" not in t.lower() else n), i + 1


def parse_table(toks, i):
    out, nexti = {}, 1
    while toks[i] != "}":
        if toks[i] == "[":
            key, i = parse_value(toks, i + 1)
            i += 2  # "]" and "="
            out[key], i = parse_value(toks, i)
        elif i + 1 < len(toks) and toks[i + 1] == "=" and re.match(r"[A-Za-z_]", toks[i]):
            key = toks[i]
            out[key], i = parse_value(toks, i + 2)
        else:
            out[nexti], i = parse_value(toks, i)
            nexti += 1
        if toks[i] in (",", ";"):
            i += 1
    keys = list(out)
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [out[k] for k in range(1, len(keys) + 1)], i + 1
    return out, i + 1


def read_saved(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        toks = list(tokens(f.read()))
    db = {}
    i = 0
    while i < len(toks):
        name = toks[i]
        db[name], i = parse_value(toks, i + 2)
    return db.get("QuestPaceLogDB") or {}


def as_list(v):
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return [v[k] for k in sorted(v)]
    return []


# --- Merging and summarizing ---------------------------------------------

def merged_sessions(folder, until):
    """Sessions from every saved file in the folder, newest file wins on duplicates."""
    files = sorted(glob.glob(os.path.join(folder, "QuestPaceLog*.lua")), key=os.path.getmtime)
    by_start = {}
    for path in files:
        for s in as_list(read_saved(path).get("sessions")):
            if isinstance(s, dict) and s.get("startedAt"):
                by_start[s["startedAt"]] = s
    out = [by_start[k] for k in sorted(by_start)]
    if until:
        out = [s for s in out if (s.get("startedAtStr") or "")[:10] <= until]
    return out


def last_moment(s, quests_only=False):
    """The session's last recorded moment. Quest time spans count quest events only."""
    times = []
    for e in as_list(s.get("entries")):
        times += [e.get("acceptedAt"), e.get("turnedInAt")]
    if quests_only:
        times = [t for t in times if t]
        return max(times) if times else None
    for r in as_list(s.get("rests")):
        times += [r.get("startedAt"), r.get("endedAt")]
    for d in as_list(s.get("dungeons")):
        times += [d.get("enteredAt"), d.get("leftAt")]
    times = [t for t in times if t]
    return max(times) if times else None


def level_times(sessions):
    """Seconds played at each level, the same way the addon's dashboard works it out.
    Sessions from 1.8 on know their start level and level-ups. Older ones are
    estimated from the levels quests and dungeons recorded, each level-up placed
    halfway between the last moment at the old level and the first at the new one."""
    out, est = collections.defaultdict(float), set()
    for s in sessions:
        start = s["startedAt"]
        end = s.get("lastActiveAt") or last_moment(s) or start
        if s.get("startLevel"):
            t0, lvl = start, s["startLevel"]
            for lu in as_list(s.get("levelUps")):
                out[lvl] += max(0, lu["at"] - t0)
                t0, lvl = lu["at"], lu["level"]
            out[lvl] += max(0, end - t0)
            continue
        pts = []
        for e in as_list(s.get("entries")):
            pts += [(e["acceptedAt"], e["acceptedLevel"])] if e.get("acceptedAt") and e.get("acceptedLevel") else []
            pts += [(e["turnedInAt"], e["turnedInLevel"])] if e.get("turnedInAt") and e.get("turnedInLevel") else []
        for d in as_list(s.get("dungeons")):
            pts += [(d["enteredAt"], d["enteredLevel"])] if d.get("enteredAt") and d.get("enteredLevel") else []
            pts += [(d["leftAt"], d["leftLevel"])] if d.get("leftAt") and d.get("leftLevel") else []
        if not pts:
            continue
        pts.sort()

        def add(level, sec):
            out[level] += max(0, sec)
            est.add(level)
        add(pts[0][1], pts[0][0] - start)
        for (ta, la), (tb, lb) in zip(pts, pts[1:]):
            mid = tb if la == lb else (ta + tb) / 2
            add(la, mid - ta)
            add(lb, tb - mid)
        add(pts[-1][1], max(end, pts[-1][0]) - pts[-1][0])
    return [{"level": lvl, "sec": round(out[lvl]), "estimated": lvl in est} for lvl in sorted(out)]


def character(name, sessions):
    info = []
    for idx, s in enumerate(sessions, 1):
        last = s.get("lastActiveAt") or last_moment(s)
        entries = as_list(s.get("entries"))
        info.append({
            "index": idx,
            "date": (s.get("startedAtStr") or "")[:10] or None,
            "loggedSec": (last - s["startedAt"]) if last else None,
            "accepted": sum(1 for e in entries if e.get("acceptedAt")),
            "turnedIn": sum(1 for e in entries if e.get("turnedInAt")),
            "xp": s.get("xpTotal"),
            "restCount": len(as_list(s.get("rests"))),
            "restSec": sum(r.get("durationSec") or 0 for r in as_list(s.get("rests"))),
        })

    # One record per quest, stitching an accept in one session to its turn-in in a later one.
    quests, open_by_id = [], {}
    for idx, s in enumerate(sessions, 1):
        for e in as_list(s.get("entries")):
            qid = e.get("questID")
            q = open_by_id.get(qid) if not e.get("acceptedAt") else None
            if q is None:
                q = {"title": e.get("title") or "?", "acceptedAt": e.get("acceptedAt"), "acceptedSession": idx if e.get("acceptedAt") else None,
                     "levelFrom": e.get("acceptedLevel"), "backlog": False}
                quests.append(q)
            q["backlog"] = q["backlog"] or bool(e.get("backlog"))
            if e.get("turnedInAt"):
                q.update(turnedInAt=e["turnedInAt"], turnedInSession=idx, levelTo=e.get("turnedInLevel"), xp=e.get("xpReward"))
                open_by_id.pop(qid, None)
            else:
                open_by_id[qid] = q

    def quest_time(q):
        """Accept to turn-in, minus the time between sessions when it spans more than one."""
        if not (q.get("acceptedAt") and q.get("turnedInAt")):
            return None, False
        a, t = q["acceptedSession"], q["turnedInSession"]
        if a == t:
            return q["turnedInAt"] - q["acceptedAt"], False
        def played(k):
            last = last_moment(sessions[k - 1], quests_only=True)
            return (last - sessions[k - 1]["startedAt"]) if last else 0
        total = sessions[a - 1]["startedAt"] + played(a) - q["acceptedAt"]
        for k in range(a + 1, t):
            total += played(k)
        total += q["turnedInAt"] - sessions[t - 1]["startedAt"]
        return max(0, total), True

    out_quests, paced = [], []
    for order, q in enumerate(quests, 1):
        sec, estimated = quest_time(q)
        # A backlog quest counts as backlog once turned in. One still open is in the log.
        status = ("backlog" if q["backlog"] else "completed") if q.get("turnedInAt") else "inlog"
        if status == "completed" and sec is not None and not q["backlog"]:
            paced.append(sec)
        out_quests.append({
            "order": order, "title": q["title"], "status": status, "backlog": q["backlog"],
            "timeSec": sec, "estimated": estimated, "xp": q.get("xp"),
            "levelFrom": q.get("levelFrom"), "levelTo": q.get("levelTo"),
            "acceptedSession": q.get("acceptedSession"), "turnedInSession": q.get("turnedInSession"),
        })

    xp_sessions = [s for s in sessions if s.get("xpTotal") is not None]
    played = sum(i["loggedSec"] or 0 for i in info)
    xp_played = sum(i["loggedSec"] or 0 for i, s in zip(info, sessions) if s.get("xpTotal"))
    turned_in = [e for s in sessions for e in as_list(s.get("entries")) if e.get("turnedInAt")]
    colors = collections.Counter(e.get("colorAtTurnIn") or "none" for e in turned_in)
    zones = collections.Counter(e["turnedInZone"] for e in turned_in if e.get("turnedInZone"))
    xp_total = sum(s["xpTotal"] for s in xp_sessions) if xp_sessions else None
    xp_quests = sum(s.get("xpFromQuests") or 0 for s in xp_sessions) if xp_sessions else None
    status_counts = {k: sum(1 for q in out_quests if q["status"] == k) for k in ("completed", "backlog", "inlog")}
    return {
        "name": name,
        "summary": {
            "lastPlayed": info[-1]["date"] if info else None,
            "sessions": len(info),
            "questsLogged": len(out_quests),
            "questsCompleted": status_counts["completed"],
            "pacedCount": len(paced),
            "totalQuestTimeSec": sum(paced) if paced else None,
            "avgPaceSec": round(sum(paced) / len(paced)) if paced else None,
            "longestSec": max(paced) if paced else None,
            "shortestSec": min(paced) if paced else None,
            "xpTotal": xp_total,
            "xpFromQuests": xp_quests,
            "xpOther": (xp_total - xp_quests) if xp_sessions else None,
            "xpFirstSession": next((i["index"] for i in info if i["xp"] is not None), None),
            "playedSec": played,
            "xpPerMinute": round(xp_total / (xp_played / 60)) if xp_total and xp_played >= 60 else None,
        },
        "questColors": {k: colors.get(k, 0) for k in ("red", "orange", "yellow", "green", "gray", "none")},
        "turnIns": {
            "solo": sum(1 for e in turned_in if e.get("turnedInGroupSize") == 1),
            "grouped": sum(1 for e in turned_in if (e.get("turnedInGroupSize") or 0) > 1),
            "unknown": sum(1 for e in turned_in if e.get("turnedInGroupSize") is None),
        },
        "groups": [{"session": idx, "durationSec": g.get("durationSec"), "maxSize": g.get("maxSize") or 2}
                   for idx, s in enumerate(sessions, 1) for g in as_list(s.get("groups"))],
        "levels": level_times(sessions),
        "zones": [{"zone": z, "turnedIn": n} for z, n in zones.most_common(10)],
        "questStatus": status_counts,
        "questLength": [
            {"key": "under5", "count": sum(1 for p in paced if p < 300)},
            {"key": "from5to15", "count": sum(1 for p in paced if 300 <= p <= 900)},
            {"key": "over15", "count": sum(1 for p in paced if p > 900)},
        ],
        "sessions": info,
        "quests": out_quests,
        "rests": [{"session": idx, "durationSec": r.get("durationSec"), "open": not r.get("endedAt"), "campfire": bool(r.get("campfire"))}
                  for idx, s in enumerate(sessions, 1) for r in as_list(s.get("rests"))],
        "dungeons": [{"session": idx, "name": d.get("name") or "?", "difficulty": d.get("difficultyName") or None,
                      "durationSec": d.get("durationSec"), "kills": sum(1 for b in as_list(d.get("bosses")) if b.get("success")),
                      "wipes": sum(1 for b in as_list(d.get("bosses")) if not b.get("success"))}
                     for idx, s in enumerate(sessions, 1) for d in as_list(s.get("dungeons")) if d.get("durationSec") is not None],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wtf", default=WTF)
    ap.add_argument("--out", required=True)
    ap.add_argument("--until", help="only sessions started on or before this date, YYYY-MM-DD")
    args = ap.parse_args()
    chars = []
    for folder in sorted(glob.glob(os.path.join(args.wtf, "*", "*", "*", "SavedVariables"))):
        sessions = merged_sessions(folder, args.until)
        if sessions:
            chars.append(character(os.path.basename(os.path.dirname(folder)).split("-")[0], sessions))
    if not chars:
        sys.exit("No QuestPaceLog saved data found under " + args.wtf)
    data = {"schemaVersion": 3, "tool": "questpacelog", "generatedOn": datetime.date.today().isoformat(),
            "game": "WoW Forever beta", "characters": chars}
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("Wrote", args.out, ", ".join(f"{c['name']} {c['summary']['sessions']} sessions" for c in chars))


if __name__ == "__main__":
    main()
