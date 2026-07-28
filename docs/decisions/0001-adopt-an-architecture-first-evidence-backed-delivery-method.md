# ADR-0001: Adopt an architecture-first, evidence-backed delivery method

Status: Accepted (2026-07-28)

## Context

This repository will grow into a production-inspired cloud platform, built
and documented so that a reader can follow the reasoning, reproduce the
work, and check the claims. At this point it contains only its foundation
files. The first real choice is not a technology but a working method,
because the method decides what every later piece of work must leave behind.

## Considered Options

**1. Implementation-first, documentation later.**
Build the platform, then write about it. This gives the fastest visible
progress and is how most personal infrastructure projects run. It also
produces documentation written backwards: reasoning is reconstructed from
memory, rejected alternatives disappear, and the docs tend to justify what
exists instead of explaining why it should exist.

**2. Lightweight design notes.**
Keep informal notes alongside the work, with no fixed format or decision
record. The overhead is low and some reasoning survives. In practice, notes
scatter and decay, and they rarely say what was rejected or what it would
take to change course. A reader can see what was done but cannot judge
whether it was sound.

**3. Architecture-first delivery with recorded decisions and evidence.**
Document requirements and reasoning before building. Record significant
choices in focused decision records. Treat a claim as unproven until real
validation evidence backs it. This is the slowest path to a first running
system and the most durable path to a system a stranger can trust.

## Decision

Adopt option 3. In practice this means:

- Requirements and reasoning are documented before implementation begins.
- Significant choices are recorded in focused ADRs like this one: one
  decision per record, with credible alternatives, consequences, and a
  revisit trigger.
- Implementation starts only after the decision it depends on is approved.
- Completion and capability claims require validation evidence captured
  when the work is executed. Failed validation is recorded when it affects
  the result.
- Each topic follows the same flow: Why → Requirements → Architecture →
  Decision → Diagram → Implementation → Validation → Evidence → Lessons
  Learned.
- Directories and files are created only when they hold real content.

## Consequences

Gained: reasoning that can be reviewed rather than taken on trust, work
that can be reproduced from the repository's documented prerequisites,
implementation artifacts, and validation steps, claims that can be checked
against captured evidence, and a record of the alternatives that lost.

Paid for: planning time before any implementation, evidence collection for
material implementation and capability claims, decision records that must
be maintained and superseded correctly as choices change, and a standing
risk of over-documentation that has to be actively resisted rather than
assumed away.

## Revisit Trigger

Revisit this method if it repeatedly slows delivery without a matching gain
in decision quality, reproducibility, evidence quality, or learning value.
One slow stretch is expected and does not qualify; a repeating pattern
does.
