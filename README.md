# Cloud Platform Reference

A production-inspired cloud platform, designed and documented from first
principles, to be implemented step by step with evidence.

## Why This Project Exists

Finished infrastructure rarely explains itself. Why each component exists,
which alternatives were rejected, what the operational tradeoffs were: that
reasoning usually disappears once something works.

This repository keeps the reasoning. Each architectural decision is written
down with its context, alternatives, and tradeoffs, and no implementation
claim stands without captured evidence.

## Who This Is For

- **Recruiters and hiring managers**: a quick read on scope, engineering
  decisions, and engineering quality.
- **Senior engineers**: architecture, decision records, and operational
  evidence as they are added, in enough depth to judge the work.
- **Engineers learning platform work**: the reasoning behind each choice,
  not just the commands.

## How This Repository Is Organized

The foundation documents are the place to start:

- [Project Charter](docs/project-charter.md): why the project exists and what governs it
- [Platform Capability Model](docs/capability-model.md): what the platform must be able to do
- [Requirements Baseline](docs/requirements-baseline.md): the measurable conditions the platform must satisfy

Decisions are recorded in [docs/decisions](docs/decisions/), starting with the working
method itself ([ADR-0001](docs/decisions/0001-adopt-an-architecture-first-evidence-backed-delivery-method.md)).

Each platform topic follows the same documentation flow:

Why → Requirements → Architecture → Decision → Diagram → Implementation →
Validation → Evidence → Lessons Learned

## Current Status

Foundation documents are in place: the project charter, platform capability model,
requirements baseline, and the first decision record. System context and logical
architecture are next; implementation has not started.

## License

Apache License 2.0. See [LICENSE](LICENSE).
