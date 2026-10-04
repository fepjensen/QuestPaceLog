"""Self-check for export_site.py. Run with python tools/test_export_site.py."""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_site as X

# A backup holding session 1, and the live file where the save bug lost it but
# session 2 finished a quest accepted in session 1.
BACKUP = '''QuestPaceLogDB = {
["sessions"] = {
{ ["startedAt"] = 1000, ["startedAtStr"] = "2026-09-22 10:00:00", ["xpTotal"] = 500, ["xpFromQuests"] = 200,
  ["entries"] = {
    { ["questID"] = 1, ["title"] = "Rude \\"Awakening\\"", ["acceptedAt"] = 1100, ["acceptedLevel"] = 1, ["turnedInAt"] = 1200, ["turnedInLevel"] = 2, ["xpReward"] = 200, ["durationSec"] = 100 }, -- [1]
    { ["questID"] = 2, ["title"] = "Long One", ["acceptedAt"] = 1300, ["acceptedLevel"] = 2 },
  },
  ["rests"] = { { ["startedAt"] = 1350, ["endedAt"] = 1400, ["durationSec"] = 50 } },
},
},
}
'''
LIVE = '''QuestPaceLogDB = {
["sessions"] = {
{ ["startedAt"] = 5000, ["startedAtStr"] = "2026-09-23 10:00:00",
  ["entries"] = { { ["questID"] = 2, ["title"] = "Long One", ["turnedInAt"] = 5100, ["turnedInLevel"] = 3, ["xpReward"] = 300, ["backlog"] = true } },
},
},
}
'''

with tempfile.TemporaryDirectory() as wtf:
    folder = os.path.join(wtf, "acct", "realm", "Hero-Realm", "SavedVariables")
    os.makedirs(folder)
    for name, body, mtime in (("QuestPaceLog-2026-09-22.lua", BACKUP, 1), ("QuestPaceLog.lua", LIVE, 2)):
        path = os.path.join(folder, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(body)
        os.utime(path, (mtime, mtime))
    out = os.path.join(wtf, "out.json")
    subprocess.run([sys.executable, os.path.join(HERE, "export_site.py"), "--wtf", wtf, "--out", out], check=True, capture_output=True)
    data = json.load(open(out, encoding="utf-8"))

c = data["characters"][0]
assert c["name"] == "Hero"
assert c["summary"]["sessions"] == 2, "backup and live file merged"
assert c["quests"][0]["title"] == 'Rude "Awakening"', "escaped quotes read"
long_one = c["quests"][1]
assert long_one["acceptedSession"] == 1 and long_one["turnedInSession"] == 2, "stitched across sessions"
# Session 1's quest events end at 1300, so 0 seconds after the accept, plus 100 into session 2.
assert long_one["timeSec"] == 100 and long_one["estimated"], long_one
assert long_one["status"] == "backlog", "turned-in backlog quest"
assert c["sessions"][0]["loggedSec"] == 400, "logged time counts the rest ending at 1400"
assert c["summary"]["pacedCount"] == 1 and c["summary"]["avgPaceSec"] == 100
assert c["summary"]["xpTotal"] == 500 and c["summary"]["xpFirstSession"] == 1
print("export_site self-check passed")
