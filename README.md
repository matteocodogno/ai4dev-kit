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
| `ai4dev review <file>` | Reviews a file with **your** review prompt |
| `ai4dev commit` | Writes a commit message from the staged diff |
| `ai4dev costs` | Your spend, your remaining budget, where your traces are |
| `ai4dev key` | Checks that your virtual key is present and your config file is locked down |
| `ai4dev config` | Shows the resolved configuration |

Three things worth knowing about how it works:

**It never names a model.** It asks for a *role*: `reviewer`, `committer`, `architect`, `tester`. Which model answers is decided on the gateway, by someone else. You will notice this in Module 1 and it comes back in Module 11.

**It never prints your key in full.** `ai4dev config` and `ai4dev key` show the first few characters and the permissions of the file holding it, never the whole thing. `doctor` fails if that file is readable by anyone else on the machine.

**Your key is low-stakes on purpose.** It is capped at a fixed budget, it lives only as long as the course, and one call revokes it. That is why it can arrive by Slack DM instead of through a secret manager: the control is sized to the risk. Ask yourself whether the same reasoning holds for your employer's provider keys. It usually does not, and noticing the difference is the actual skill.

**It reads its prompts from here.** Edit `prompts/code_review.md` and the behaviour of `ai4dev review` changes in every repository you work in. That is what "true of you" means, made executable.

---

## Layout

```
ai4dev-kit/
├── bin/ai4dev            the tool
├── config.example        copy to ~/.config/ai4dev/config
├── prompts/              your prompts          — Module 1 onward
│   ├── code_review.md
│   └── commit_message.md
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
