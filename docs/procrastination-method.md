# How Still approaches procrastination

Still started as a quiet focus timer. This note records the thinking behind where it is
going: what procrastination is, the mindset Still tries to support, the design rules that
follow, and how research mode measures your own pattern. It draws mainly on Timothy A.
Pychyl, *Solving the Procrastination Puzzle* (Tarcher/Penguin, 2013), and on later research
noted below. It is a summary in our own words, not a substitute for the book.

## The model in one paragraph

Procrastination is a *needless, voluntary* delay of something you intended to do, despite
knowing the delay will probably cost you. Plenty of delay is not procrastination: a sick
child, missing information or a genuinely higher priority are good reasons to wait. The
needless kind is mostly an **emotion-regulation problem**, not a time-management one. A
task feels bad (boring, unclear, frustrating, threatening), putting it off brings instant
relief, and that relief rewards the delay until it becomes a habit. We then justify it,
most often with "I'll feel more like it tomorrow", which is a forecasting error: we will
not. Because the habit runs without much thought, in-the-moment willpower is a weak tool.
What works better is **deciding in advance** (if–then plans, or implementation intentions),
**just getting started** on any concrete piece, preparing for the distractions that come
after starting, and **forgiving yourself** after a slip so that you approach the task again
instead of avoiding it.

## Mindset

1. **Not all delay is procrastination.** Only the needless kind is worth fighting.
2. **Name the feeling you are escaping.** Bored, unsure where to start, worried it won't be
   good, frustrated, tired. Naming it weakens the pull.
3. **"I'll feel more like it later" is a cue, not a forecast.** Hearing it is the signal to
   start.
4. **Motivation follows action.** You do not need to feel like it first.
5. **Start small and concrete.** Open the file, write the heading, do the first visible
   step. Restarting many times a day is normal.
6. **Decide while calm.** Write your own if–then plans for starting, for distractions and
   for getting stuck. Let the situation trigger the plan instead of re-deciding.
7. **Remove before you resist.** Closing distractions in advance beats fighting them later.
8. **"It'll only take a minute" is a decision you make again every minute.**
9. **Hard things go earlier in the day; sleep is the foundation.**
10. **Forgive and restart.** Self-criticism after a slip feeds avoidance; forgiveness
    brings you back.

## Design rules for Still

| Rule | Why |
|---|---|
| An intention comes first. Every focus session should know what it is for. | Without an intention there is only delay, not procrastination. |
| Interrupt only at the moment of the cue, using **your** words. | If–then plans work because they are your own advance decisions. |
| Count starts, not only completions. A five-minute start counts. | Getting started is the main lever. |
| Let forecasts meet reality: rate how bad a task looks before, and how it felt after. | Tasks are usually less aversive once started; your own data is the best evidence. |
| Help remove distractions before relying on reminders. | Advance removal beats in-the-moment resistance. |
| Legitimate delay is not failure; a missed day gets forgiveness, not a red mark. | Self-forgiveness reduces later procrastination. |
| Keep a quiet budget: few interruptions, the rest goes to review. | Too many prompts cause reactance, and the tool gets switched off. |
| Make loosening a setting a decision for later, tightening immediate. | People soften their tools in the moment, which is the same "later" error. |
| Treat every feature as an experiment with a measure and a way to drop it. | Change comes from doing, not from more tooling. |
| Behavior data stays on the Mac. No accounts, no network. | Privacy is part of trust. |

## What exists and what is planned

| Idea | In Still |
|---|---|
| Focus timer, daily goal, Markdown journal | Available |
| Distraction and inactivity reminders during focus | Available |
| Research mode: random check-ins that measure your own procrastination | Available |
| One-line intention and first step at start; "start for five minutes" | Planned |
| Rate expected vs actual discomfort; reasons for stopping or postponing, split into legitimate delay and rationalizations | Planned |
| A library of your own if–then plans, shown when their cue happens | Planned |
| Daily plan as a few commitments with a time and a first step, opened when the time comes | Planned |
| An all-day, local activity record (app, site, idle) classified relative to your intention, to notice "sat down but never started" | Planned |
| Weekly review: your most common feelings, excuses, destinations and risky hours | Planned |

## Research mode

Research mode applies experience sampling, the method Pychyl's group used with pagers, to
your own working days.

**Protocol.** You choose a length (default 14 days), check-ins per day (default 4) and a
daily window (default 10:00–23:00). Each day's window is split into equal blocks and one
check-in falls at a random point in the middle 80% of each block, so prompts are
unpredictable but never bunched together. The schedule is derived from the study's
identifier: it survives relaunches and is never shown in advance.

**At a check-in.** If you are at the Mac (recent input, unlocked, no bedtime or completion
panel), Still plays your inactivity sound and asks: *Is there something else you should be
doing right now?* If yes, you pick how that task feels and can name it. Still records the
app, window title and page or document you were on at that moment.

**Complete record.** Every scheduled check-in produces exactly one journal note, whatever
happened:

| Outcome | Meaning |
|---|---|
| `answered` | You answered; `elsewhere` is `yes` or `no` |
| `skipped` | You chose Skip |
| `expired` | No answer within 10 minutes |
| `in-focus` | A focus session was running; context recorded without interrupting |
| `missed` | Nobody saw it within 45 minutes; `missedReason` is `still-not-running`, `mac-asleep` or `away` |
| `interrupted` | Still quit or crashed while it was open, before the first question was answered |

If Still quits or crashes after you answered "Yes" but before saving, the note keeps what
was entered (`complete: no`, `interruptedBy: quit` or `unexpected-exit`). The open check-in
is mirrored to a small local file whenever you make a choice, so even a crash or power loss
leaves a record; the next launch writes it.

A start note and an end note with totals frame each study, and launches and quits during a
study are noted, so gaps in coverage are visible. Notes use a separate journal marker that
older releases ignore.

**What it can tell you.** The share of sampled moments in which you felt you should be
doing something else (your personal baseline), how that varies by hour and by app or site,
and which feelings dominate, for example boredom and unclear next steps versus worry about
quality. Those answers decide which of the planned features matter most for you.

**Limits.** Four prompts a day for two weeks is about fifty answers: enough for a baseline
and rough patterns, not for fine-grained statistics. Self-report shapes behavior a little;
treat the first days as warm-up. Away time is only counted as missed, not interpreted.

## Measuring computer behavior

The planned activity record is built into Still rather than borrowed from another tracker:

- Still already has the one permission that matters (Accessibility) and code that reads the
  active browser page. Window titles also need only Accessibility; Still will not request
  Screen Recording.
- Value comes from context. "Two hours of video" says less than "seven minutes after
  starting the report, you switched to a video site and came back three minutes later".
  Only an in-app record can align activity with your intention, if–then plans and reasons.
- Apple's Screen Time APIs are not available to native macOS apps, and the on-disk
  Screen Time stores are undocumented; they are useful at most as a cross-check.
- Defaults: event-driven capture (no screenshots, no keystroke content), app and domain
  only, window titles opt-in per app, full URLs opt-in, private windows skipped, data in a
  local SQLite file, daily summaries in the journal.

## Evidence notes

- **Strong:** procrastination as short-term mood repair; task aversiveness as a key
  situational driver; conscientiousness as the main protective trait; implementation
  intentions (a 2006 meta-analysis of 94 studies found a medium-to-large effect; later
  preregistered studies find smaller but consistent effects, best when plans are
  self-written and specific).
- **Moderate:** tasks feel less aversive once started (experience-sampling studies with
  small student samples); self-forgiveness reducing later procrastination; "working better
  under pressure" being mostly a rationalization.
- **Weak:** willpower as a depletable resource and the glucose account of it did not hold
  up in large preregistered replications. Still does not model "willpower battery"; it keeps
  the sturdier advice: protect sleep, schedule hard work earlier, use advance plans.
- **Digital self-control tools:** friction prompts reduce compulsive opening in the short
  term; long-term effects are unclear, people rebound after breaks, and strict blocking
  invites workarounds. Hence a quiet budget and measured, reversible features.

## References

- Pychyl, T. A. (2013). *Solving the Procrastination Puzzle: A Concise Guide to Strategies for Change.* Tarcher/Penguin.
- Sirois, F., & Pychyl, T. (2013). Procrastination and the priority of short-term mood regulation. *Social and Personality Psychology Compass*, 7(2), 115–127.
- Steel, P. (2007). The nature of procrastination: A meta-analytic and theoretical review. *Psychological Bulletin*, 133(1), 65–94.
- Gollwitzer, P. M., & Sheeran, P. (2006). Implementation intentions and goal achievement: A meta-analysis. *Advances in Experimental Social Psychology*, 38, 69–119.
- Wohl, M. J. A., Pychyl, T. A., & Bennett, S. H. (2010). I forgive myself, now I can study. *Personality and Individual Differences*, 48(7), 803–808.
- Hagger, M. S., et al. (2016). A multilab preregistered replication of the ego-depletion effect. *Perspectives on Psychological Science*, 11(4), 546–573.
- Grüning, D. J., Riedel, F., & Lorenz-Spreen, P. (2023). Directing smartphone use through the self-nudge app one sec. *PNAS*, 120(8).
- Nahum-Shani, I., et al. (2018). Just-in-time adaptive interventions (JITAIs) in mobile health. *Annals of Behavioral Medicine*, 52(6), 446–462.
