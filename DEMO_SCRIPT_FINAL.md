# Mosaic — Final Demo Video Script (3 minutes)

Per the Somnia devs' note: **3 minutes max, sound like a person, not a script.**
The narration below is written the way you'd actually say it out loud — short
sentences, contractions, plain words. Don't read it word-for-word in a flat
voice; glance at each beat, then say it like you're showing a friend something
you built. Pauses are fine. A small stumble is fine — it sounds human.

**Before you hit record:**
- All three runners up (`guardian`, `summarizer`, `composer`) — check terminals.
- Deactivate the dead duplicate agent so the marketplace looks clean.
- Use agent 4 for the summarizer, agent 5 for the composer.
- Have a contract address copied (your MosaicHub: `0x885eEd164a427939E69dB1bC28b55Fca5cD60b93`).
- Browser zoom ~110% so text is readable on small screens.
- Close noisy tabs/notifications.

**Tone reminders:** lead with what it *does*, not what it's *built on*. Say
"it" and "you" a lot. Avoid "leverage, robust, seamless, cutting-edge." If a
sentence sounds like a whitepaper, cut it.

---

## [0:00–0:20] — Open on the marketplace grid

*(Screen: the homepage, agents listed.)*

> "So this is Mosaic. It's a marketplace for AI agents that runs entirely on
> Somnia. The idea's pretty simple — anyone can publish an agent, anyone can
> pay to use one, and every job it does gets recorded on-chain. No backend, no
> database. If it's here, it's real."

*(Slowly scroll the grid so the live/idle dots and reputation badges are visible.)*

> "Each card shows what the agent does, what it costs, and how reliable it's
> been. That green dot means its runner's online right now."

---

## [0:20–1:00] — Guardian scan (the flagship)

*(Click into Guardian / the Scanner page. Paste a contract address.)*

> "Let's start with our security agent — Guardian. I'll give it a contract
> address and ask it to scan it."

*(Click Request scan. Wallet pops up — approve it.)*

> "That's one real transaction on Somnia. Guardian pulls the contract's
> bytecode, checks it for risky stuff — things like self-destruct or
> delegatecall — and scores it."

*(Result appears — point at the score and findings.)*

> "And there's the report. A risk score, the exact findings, and a link to the
> transaction. So this isn't a number I made up — you can click through and
> verify it on the explorer yourself."

*(Briefly click the explorer link, let it load, come back.)*

---

## [1:00–1:40] — Generic invoke (it's a real marketplace)

*(Go to the Summarizer's agent page, agent 4.)*

> "Guardian's the flagship, but the whole point is that *any* agent works the
> same way. Here's a totally different one — a text summarizer someone could
> drop in."

*(Type a sentence or two into the box. Click Invoke.)*

> "I just type what I want, pay the fee, and the agent's runner picks it up off
> the chain, does the work, and signs the result back."

*(Result appears with the two tx links.)*

> "Same pattern, different agent. Two transactions — the request and the
> signed answer — both right there to check. That's what makes it a
> marketplace and not just one demo app."

---

## [1:40–2:30] — Composer (the headline: agents using agents)

*(Go to the Composer's page, agent 5. Set goal = audit_and_explain, target = the contract address.)*

> "Now the part I'm most proud of. This one's a meta-agent — it doesn't do the
> work itself, it *hires other agents* to do it."

*(Click Invoke. While it runs, switch to show the guardian + summarizer terminals lighting up.)*

> "Watch — I asked it to audit a contract and then explain it in plain English.
> Behind the scenes it's looking at the marketplace, picking the best security
> agent by reputation, paying it to run the scan… and then it takes those
> findings and hands them to the summarizer to write up."

*(Come back to the result when it lands.)*

> "So that's three agents working together, settled across real transactions,
> with one agent's output becoming the next one's input. That's the thing
> Somnia makes possible — fast, cheap, final settlement is what lets agents
> actually coordinate like this."

---

## [2:30–3:00] — Close (credibility + why it matters)

*(Cut to the repo — show the test suite passing, or the ARCHITECTURE.md / README.)*

> "Quick note on the engineering: the contracts have a full test suite that
> runs in CI, and there's a doc that walks through the tricky design calls —
> why payments are pull-based, how a contract can own its own agent identity,
> that kind of thing."

*(Back to the marketplace grid for the final shot.)*

> "That's Mosaic — a place where agents discover each other, pay each other,
> build a reputation, and team up. All on Somnia. Thanks for watching."

*(End.)*

---

## Timing cheat-sheet

| Section | Target | Running total |
|---|---|---|
| Open / marketplace | 0:20 | 0:20 |
| Guardian scan | 0:40 | 1:00 |
| Generic invoke | 0:40 | 1:40 |
| Composer | 0:50 | 2:30 |
| Close | 0:30 | 3:00 |

If you're running long, the easiest cut is the explorer click-through in the
Guardian section — say "you can verify it on the explorer" without actually
clicking. Protect the Composer segment; that's the differentiator.

## Recording tips that kill the "AI voice"
- Record narration and screen separately if you can — talk through it once
  without worrying about clicks, then line it up. Your voice relaxes when
  you're not also driving the mouse.
- Do two or three takes and keep the most natural one, not the most "correct."
- Smile slightly while talking — it genuinely changes the tone.
- Leave the small "umm let me show you" moments in. Polished-but-human beats
  flawless-but-robotic every time.
- Don't speed-read to hit 3:00. Better to cut a sentence than to rush.
