# ai4dev-kit

**Your kit. It is true of you, not of any codebase, and it follows you into every repository you work in.**

This repository holds two things: the `ai4dev` command line tool, and the content it reads. Both are yours from the moment you clone it. You will commit to it at the end of every module of the course, and you take it home at the end.

---

## What goes in here, and what does not

The rule, and it is the whole point of Module 1:

> **Is this true of the code, or true of me?**
>
> An instruction that describes *a codebase* — its conventions, its build, its gates — belongs in that repository, and it is reviewed like code.
>
> An instruction that describes *how you work* — your review prompt, your checklists, your skills — belongs here, because it travels with you.

Nothing in here is product code. Nothing in a product repository is a copy of what is in here.

---

## Install

**On Windows, do all of this inside WSL2 with Ubuntu**, not in PowerShell and not in Git Bash. The tool is a bash script and it checks Unix file permissions; inside WSL2 everything below behaves exactly as it does on a Mac.

```bash
git clone https://github.com/matteocodogno/ai4dev-kit.git ~/ai4dev-kit
echo 'export PATH="$HOME/ai4dev-kit/bin:$PATH"' >> ~/.zshrc   # Ubuntu/WSL2: ~/.bashrc
exec $SHELL -l
ai4dev version
```

The course's assistant is **OpenCode**. Install it now; you connect it to the gateway on day 1, with one command, once you have a key.

```bash
brew install anomalyco/tap/opencode     # or: curl -fsSL https://opencode.ai/install | bash
opencode --version
```

Then create your configuration from the example and lock it down. The gateway URL is `https://aiproxy.ai4dev.dev/v1`; the dashboard is `https://langfuse.ai4dev.dev`. **Leave the key line empty** — the key is issued in the room on day 1.

```bash
mkdir -p ~/.config/ai4dev
cp config.example ~/.config/ai4dev/config
chmod 600 ~/.config/ai4dev/config
$EDITOR ~/.config/ai4dev/config
```

Set the permissions now anyway: in a few days that file holds your key, and `ai4dev doctor` refuses to pass if it is readable by anyone else on the machine.

And verify:

```bash
ai4dev doctor
```

Before day 1 it will report **`no virtual key yet`** in yellow and, if everything else is green, finish with **`ready for day 1`**. That is the correct result and there is nothing to fix. Once you paste the key in, the same command makes one real request through the course gateway and prints your remaining budget.

---

## Commands

| Command | What it does |
| --- | --- |
| `ai4dev init` | Clones the course repositories into `~/ai4dev` |
| `ai4dev doctor` | Verifies the environment. With a key, makes one real request; without one, says *ready for day 1* |
| `ai4dev ask <prompt>` | Asks an alias directly and tells you what the answer cost |
| `ai4dev code` | Starts OpenCode against the course gateway, with your key borrowed for the life of one process |
| `ai4dev review <file>` | Reviews a file with **your** review prompt |
| `ai4dev commit` | Writes a commit message from the staged diff |
| `ai4dev costs` | Your spend, your remaining budget, where your traces are |
| `ai4dev costs --last N` | The last N requests: tokens in and out, cost, latency, which model answered |
| `ai4dev key` | Checks that your virtual key is present and your config file is locked down |
| `ai4dev config` | Shows the resolved configuration |
| `ai4dev upgrade` | Updates the tool from the course, and touches nothing else |

Three things worth knowing about how it works:

**It never names a model.** It asks for a *role*: `reviewer`, `committer`, `architect`, `tester`. Which model answers is decided on the gateway, by someone else. You will notice this in Module 1 and it comes back in Module 11.

**It lends your key rather than exporting it.** `ai4dev code` starts OpenCode with `AI4DEV_API_KEY` set for that one process, then gets out of the way. The OpenCode config it writes at `~/.config/opencode/opencode.json` names the gateway and the three aliases and contains the string `{env:AI4DEV_API_KEY}` — not your key. That file is safe to read, copy or screenshot. The usual shortcut, exporting the key from your shell profile, puts it in the environment of every process you start for the rest of the week.

**So start OpenCode with `ai4dev code`, never with a bare `opencode`.** A bare `opencode` starts anyway and warns about nothing: the variable is simply not set, so the requests go out with no key on them and the gateway answers 401. That looks exactly like a broken key and is not one — it is the key not being there.

**It never prints your key in full.** `ai4dev config` and `ai4dev key` show the first few characters and the permissions of the file holding it, never the whole thing. `doctor` fails if that file is readable by anyone else on the machine.

**Your key is low-stakes on purpose.** It is capped at a fixed budget, it lives only as long as the course, and one call revokes it. That is why it can arrive by Slack DM instead of through a secret manager: the control is sized to the risk. Ask yourself whether the same reasoning holds for your employer's provider keys. It usually does not, and noticing the difference is the actual skill.

**It reads its prompts from here.** Edit `prompts/code_review.md` and the behaviour of `ai4dev review` changes in every repository you work in. That is what "true of you" means, made executable.

---

## `ask`, and the ledger behind it

`review` and `commit` send a prompt from this kit. `ask` sends exactly what you typed, to exactly the alias you named, and then tells you what it cost. It is the command for measuring a model rather than using one.

```bash
ai4dev ask "In two sentences: why might a Chihuahua and a Husky be a poor match?"
ai4dev ask --model cheap --temp 0.0 --n 5 "…"
ai4dev ask --model open-hosted --prompt-file brief.md
```

| Flag | What it does |
| --- | --- |
| `--model <alias>` | `frontier`, `cheap`, `open-hosted`, `reviewer`, `committer`, … Still an alias, never a model name |
| `--temp <n>` | Sent **only if you pass it**. Some aliases reject it outright, and when that happens the error explains why rather than hiding it |
| `--n <count>` | Run the same prompt 1 to 20 times. The point is to watch what changes between runs |
| `--prompt-file <path>` | Read the prompt from a file |

Every request the tool makes is appended to `~/.local/state/ai4dev/usage.jsonl`, and `ai4dev costs --last 3` reads it back:

```
when (UTC)           alias        model that answered             in     out       cost    secs
2026-09-17T09:41:02  frontier     anthropic/claude-sonnet-5     1083     241   0.000369    7.39
2026-09-17T09:42:40  cheap        openai/gpt-5.6-luna           1083     198   0.000041    1.82
```

You now have three records of the same request and they do not say the same thing. The gateway knows what it charged you. The dashboard knows what was sent and what came back. This file knows **how long you waited**, which neither of the other two can see, because latency is a property of where you are standing. Notice which question each one can answer, and which one you reach for.

The file is yours and it is local. Deleting it loses nothing the gateway does not still have.

---

## `upgrade`, and why it is not `git pull`

This kit holds two different things: a tool the course ships and keeps changing, and work that is yours from Kit Zero onward. From Module 2 your branch has commits the course does not have, so a fast-forward pull is not even on the table, and a merge would make you resolve a conflict between the course's tool and your own history.

`ai4dev upgrade` does not pull. It takes the **course-owned paths** — `bin/`, `README.md`, `config.example` — from the course's `main` and commits only those.

```bash
ai4dev upgrade
```

Your prompts, checklists, decisions and notes are never touched, so there is nothing to resolve: the two sets of files do not overlap. If you have uncommitted edits to a course-owned file, it stops and tells you instead of overwriting them.

Note what this means for `prompts/`. The course seeds those files once and then they are yours — Module 3 has you rewrite `code_review.md`, and an upgrade must never undo that. That is why `prompts/` is not on the list.

---

## Layout

```
ai4dev-kit/
├── bin/ai4dev            the tool
├── config.example        copy to ~/.config/ai4dev/config
├── prompts/              your prompts          — Module 1 onward
│   ├── code_review.md
│   └── commit_message.md
├── decisions/            your decision records — Module 2 onward
├── skills/               your skills           — Module 3
├── checklists/           your checklists       — Module 1 onward
├── rubrics/              your eval rubrics     — Module 9
└── notes/                whatever you want
```

Empty directories are not a mistake. They are the shape of what you are about to build.

---

## A warning about `prompts/code_review.md`

The review prompt shipped here is **deliberately mediocre**. It finds obvious defects and stops.

Do not fix it yet. In Module 3 you will improve it against the same file you used in Module 1, and the difference will be measurable. Keep the original commit so you can see the diff.
