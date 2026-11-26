---
name: handoff
description: Update HANDOFF.md so the next Claude Code session can pick up where this one stopped, with the owner's latest decision as the next task, then land it on main. Use when the owner types /handoff or asks to write, update or refresh the handoff notes.
---

# /handoff

Bring `HANDOFF.md` (repo root) up to date with this session, then get it onto `main`.
The reader is the next Claude session, starting cold: it has only `CLAUDE.md`, this
file and the code.

## 1. Gather the facts first

- `git fetch origin`, then `git log --oneline -8 origin/main` and
  `gh release list --limit 2`: the latest merged PRs and the live release version.
- `git status` and `git branch -vv`: uncommitted or unpushed work. Work that isn't on
  `main` must be named in the notes with its branch and commit, and whether it's pushed.
  Commit loose work on its own branch first (say "WIP" and "not for merge" if so); never
  leave it only in the working tree.
- Read the current `HANDOFF.md` in full before editing it.
- From this conversation: what was fixed, what was tried and failed, what the owner
  decided, and anything the owner said about how to work.

## 2. Write the notes

Keep the existing sections and edit them in place; don't append a diary.

1. **Next task** at the top, when the owner has decided what comes next. Put the
   decision in their words ("Do ideas 1 and 2 together, in one PR") and date it. Under
   it:
   - **What's known**: observed facts, each with where it was seen (owner's device,
     simulator, which version). Separate confirmed from guessed.
   - **The plan**: numbered steps concrete enough to start on: files, functions,
     selectors, the approach. Include rejected or fallback options and why.
   - **Testing rules** the owner gave, e.g. "don't keep videos playing".
2. **Where things are**: what's on `main`, the live release, branches and their state.
3. **Build and run locally** and **Simulator pitfalls**: add anything new this session
   learned the hard way (commands that didn't work and what did).
4. **Fixed in …**: one short section per pass, with PR numbers. Collapse older passes
   to a line or two once they're settled.
5. **Still open**: numbered, one item per problem, each saying what's unverified and how
   to check it. Remove items that are done; point to "Next task" instead of repeating it.

Style: plain sentences, specifics over adjectives, code names in backticks, no secrets
(never a TMDB key or token). Keep the whole file readable in a few minutes.

## 3. Land it

Follow `CLAUDE.md`: branch from the latest `main` (e.g. `claude/handoff-<topic>`),
commit only `HANDOFF.md` (plus anything the owner asked for alongside it), push, and
open a PR. A notes-only PR doesn't trigger the "Build iOS app" check, so once GitHub
reports it mergeable and clean, squash-merge it. Report the PR link and what the next
session will start with.
