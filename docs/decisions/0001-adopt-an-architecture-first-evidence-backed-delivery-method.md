# ADR-0001: Adopt an architecture-first, evidence-backed delivery method

Status: Accepted (2026-07-28); revised 2026-10-21 with one policy change: a
proportional workflow for routine implementation within Accepted decisions.
Approval requirements and control boundaries remain binding.

## Context

The platform must be understandable, reproducible and supported by evidence.
Documentation and review effort must be proportionate to the change.

## Decision

Record significant architecture decisions before implementation. Each ADR
states the problem, selected approach, credible alternatives, consequences
and conditions for reconsidering it. The owner approves the decision, and
implementation that depends on it starts only after that approval.

For routine implementation within Accepted decisions:
- Make the smallest change that solves the problem.
- Run relevant existing checks.
- Update documentation when behavior or operating instructions change.
- Create no new ADR or additional review stage unless the change affects
  an architectural decision or an existing control requires it.

Support completion and capability claims with evidence from execution.
Retain failures and limitations that affect the result. Reuse valid evidence.

Create documents and diagrams only when they explain something necessary.
Do not repeat information already maintained elsewhere.

Existing security, authorization, cost, recovery and teardown controls
remain binding.

## Alternatives

Implementation first and documentation later risks losing the reasoning.
Informal notes reduce effort but can omit alternatives and decision history.
Focused ADRs and execution evidence provide a reviewable record.

## Consequences

Important choices remain traceable and claims remain checkable.
Planning and validation still require effort; routine changes carry only
the documentation and review they need.

## Revisit

Reconsider this method if it repeatedly delays delivery without improving
decision quality, reproducibility, evidence or learning.
