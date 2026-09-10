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

```bash
git clone <this repository> ~/ai4dev-kit
echo 'export PATH="$HOME/ai4dev-kit/bin:$PATH"' >> ~/.zshrc   # or ~/.bashrc
exec $SHELL -l
ai4dev version
```

Then create your configuration from the example. The facilitator gives you the two URLs.

```bash
mkdir -p ~/.config/ai4dev
cp config.example ~/.config/ai4dev/config
$EDITOR ~/.config/ai4dev/config
```

And verify:

```bash
ai4dev doctor
```

The last check makes one real request through the course gateway and prints your remaining budget. If it is green, you are ready for day 1 and the facilitator can see it without you reporting anything.

---

## Commands

| Command | What it does |
| --- | --- |
| `ai4dev init` | Clones the course repositories into `~/ai4dev` |
| `ai4dev doctor` | Verifies the environment, fetches your key, makes one real request |
| `ai4dev review <file>` | Reviews a file with **your** review prompt |
| `ai4dev commit` | Writes a commit message from the staged diff |
| `ai4dev costs` | Your spend, your remaining budget, where your traces are |
| `ai4dev key` | Re-fetches your virtual key from the secret manager |
| `ai4dev config` | Shows the resolved configuration |

Three things worth knowing about how it works:

**It never names a model.** It asks for a *role*: `reviewer`, `committer`, `architect`, `tester`. Which model answers is decided on the gateway, by someone else. You will notice this in Module 1 and it comes back in Module 11.

**It never writes your key to disk.** The virtual key is fetched from your secret manager on every invocation and held in memory only. `ai4dev config` deliberately does not print it.

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
├── checklists/           your checklists       — Module 8
├── rubrics/              your eval rubrics     — Module 9
└── notes/                whatever you want
```

Empty directories are not a mistake. They are the shape of what you are about to build.

---

## A warning about `prompts/code_review.md`

The review prompt shipped here is **deliberately mediocre**. It finds obvious defects and stops.

Do not fix it yet. In Module 3 you will improve it against the same file you used in Module 1, and the difference will be measurable. Keep the original commit so you can see the diff.
