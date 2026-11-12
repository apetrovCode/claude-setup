"""Run one hook's case table: run-cases.py HOOK.sh CASES.jsonl

Each line is a JSON object:
  id, why            names and the reason the case exists
  stdin | stdin_raw  the hook's input (an object, sent as JSON) or raw text
  expect             0 allow, 2 block, 1 the hook fails (onFailure "block" then blocks)
  files?             {relative path: content} written under the case's temp dir
  stubs?             {tool: shell body} executables put first on PATH
  stderr_has?        a string the hook's stderr must contain
"@TMP@" anywhere in stdin, file paths or stubs is replaced with the case's temp dir.
PATH is the stubs, jq, and /usr/bin:/bin only, so a real linter on this machine
never leaks into a case. Prints one line per failure; exits 1 if any case fails."""
import json, os, shutil, subprocess, sys, tempfile

hook, cases = sys.argv[1], sys.argv[2]
jq = shutil.which("jq")
fails, n = [], 0
for line in open(cases):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    c = json.loads(line)
    n += 1
    with tempfile.TemporaryDirectory() as tmp:
        sub = lambda s: s.replace("@TMP@", tmp)
        binp = os.path.join(tmp, ".bin")
        os.makedirs(binp)
        if jq:
            os.symlink(jq, os.path.join(binp, "jq"))
        for tool, body in c.get("stubs", {}).items():
            p = os.path.join(binp, tool)
            with open(p, "w") as f:
                f.write("#!/bin/sh\n" + sub(body) + "\n")
            os.chmod(p, 0o755)
        for rel, content in c.get("files", {}).items():
            p = os.path.join(tmp, sub(rel))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as f:
                f.write(content)
        data = sub(c["stdin_raw"]) if "stdin_raw" in c else sub(json.dumps(c["stdin"]))
        env = {"PATH": binp + ":/usr/bin:/bin", "HOME": tmp, "TMPDIR": tmp, "LC_ALL": "C"}
        try:
            r = subprocess.run(["bash", hook], input=data, text=True, capture_output=True, env=env, timeout=30)
            rc, err = r.returncode, r.stderr
        except subprocess.TimeoutExpired:
            rc, err = "timeout", ""
        problems = []
        if rc != c["expect"]:
            problems.append(f"exit {rc}, want {c['expect']}")
        if "stderr_has" in c and c["stderr_has"] not in err:
            problems.append(f"stderr lacks {c['stderr_has']!r}")
        if problems:
            fails.append(f"  {c['id']}: {'; '.join(problems)}  ({c['why']})")
print("\n".join(fails))
print(f"{n - len(fails)}/{n} cases pass")
sys.exit(1 if fails else 0)
