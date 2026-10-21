# ADR-0012: AstroShop as the reference workload

Status: Accepted (2026-08-01); revised 2026-10-21 with one policy change: the
application inventory may record published and deployed digests as
evidence, while GitOps remains the authority for deployment pins and desired
state.

## What we will use

Use AstroShop, the project's adaptation of OpenTelemetry Demo,
to validate platform capabilities.

The platform is the product. Application changes must support platform
validation. Reusing an instrumented application avoids building a new
application before platform testing can begin.

The original four-to-six-service limit was superseded by ADR-0014.
Current implementation scope follows ADR-0016 as modified by ADR-0017.

The workload must provide:

- A browser-accessible entry and real calls between separately
  deployable services, covering at least two languages or runtimes.
- Source-built containers, runtime configuration, observable health,
  multiple interchangeable instances and two visibly different versions.
- Metrics, structured logs and distributed traces with context
  propagated between services.
- A reversible fault, a runtime secret, an authenticated dependency
  and durable data that gives restore testing a meaningful subject.

Use the platform's generic onboarding path and keep external
dependencies bounded. Send telemetry only to the platform Collector.
Disable the workload's bundled Collector and observability stack.

## Ownership and reproducibility

Distinguish project-built components, justified upstream images and
components that are not deployed. ADR-0014 provides the detailed
component classification.

Build project-owned artifacts through the application pipeline.
For each deployed upstream image, record a justification and revisit
condition, mirror it into ECR, pin its digest and scan it there under
the same threshold as project-built images.

Upstream images do not carry a project-owned build history.
State provenance limits clearly. Excluded components do not run.

Put data that must survive environment teardown in a managed service
with native backup and recovery. In-cluster data must be disposable
or regenerable unless a later Accepted ADR defines another arrangement.
Validate workload-data restore under ADR-0011 and approve its persistent
cost separately.

Keep cloud-platform-workload public on GitLab. It holds source,
modifications, container definitions, available tests, pipelines,
derivation records and upstream exceptions. Another engineer must
be able to reproduce it without private repositories, private paths,
private environment access or hidden build inputs.

Document the upstream version, project changes, component selection,
exclusions and provenance. Preserve licenses and attribution with
the source. Apply existing publication controls for author identity,
secrets, internal identifiers and adapted third-party material.

GitOps owns environment values, desired state and deployment digest pins.
The application inventory may record published and deployed digests
as evidence; it does not control deployment.

The reference repository holds architecture, Terraform, implementation
documentation and sanitized evidence. Secret values belong in none
of these repositories.

Revisit if required capabilities cannot be demonstrated, upstream
maintenance or licensing becomes unsuitable, or application work
begins to displace platform work.
