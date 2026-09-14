# GitOps Delivery

How a change to application source becomes a running container on EKS, from the pipeline
that builds the image to the reconciler that applies it. The authoritative desired-state
repository, `cloud-platform-gitops`, is private because its image pins carry the account's
registry coordinates. Everything below is derived from that implementation with the private
coordinates replaced; each excerpt is a **SANITIZED IMPLEMENTATION-DERIVED EXAMPLE**, not
the live desired state.

```
GitLab CI ──▶ ECR (immutable tag, digest identity) ──▶ merge request pinning the digest
          ──▶ Argo CD renders chart + value layers ──▶ EKS
```

## 1. Build once: GitLab CI to an immutable digest

The workload pipeline runs `lint → build → scan → health-test → publish → promote`
([`.gitlab-ci.yml`](https://gitlab.com/tuinzaman/cloud-platform-workload/-/blob/main/.gitlab-ci.yml)).
Each service composes its jobs from shared templates; checkout, for example, extends the
hadolint, Go lint and test, image build, Trivy scan, container health and ECR publish
templates in
[`services/checkout/ci.yml`](https://gitlab.com/tuinzaman/cloud-platform-workload/-/blob/main/services/checkout/ci.yml).
The scan gate blocks on fixable HIGH and CRITICAL findings; no job carries `allow_failure`.

Publication ([`ci/templates/ecr-publish.yml`](https://gitlab.com/tuinzaman/cloud-platform-workload/-/blob/main/ci/templates/ecr-publish.yml))
holds no AWS credential. The job requests a GitLab ID token with audience `sts.amazonaws.com`,
exchanges it through `assume-role-with-web-identity` for credentials that expire on their own,
pushes the image under a tag derived from the commit, and records the digest **the registry
returned** rather than one computed locally:

```sh
docker push "${ECR_REGISTRY}/${ECR_REPOSITORY}:${CI_COMMIT_SHORT_SHA}"
docker inspect --format='{{index .RepoDigests 0}}' \
  "${ECR_REGISTRY}/${ECR_REPOSITORY}:${CI_COMMIT_SHORT_SHA}" | cut -d@ -f2 > digest.txt
```

ECR tags are immutable, and the digest is the artifact's identity from here on. Publishing is
a manual job on the main branch: the pipeline verifies every commit, but only a reviewed one
becomes an artifact. The registry host and role ARN are masked CI variables and never appear
in the repository.

## 2. Desired state: three value layers, image identity last

The GitOps repository holds Helm value layers and Argo CD Application definitions only. No
application source, no container definition, no pipeline, no secret value.

| Path | Owns |
|---|---|
| `base/values.yaml` | Fleet-wide invariants, identical in every environment |
| `environments/<env>/values.yaml` | Environment configuration |
| `environments/<env>/images.yaml` | Image identity for that environment, and nothing else |
| `argocd/applications/` | Argo CD Application definitions |
| `bootstrap/` | Owner-applied definitions needed before Argo CD runs; not reconciled by Argo CD |

The Dev Application enumerates the layers explicitly, and later files win, so image identity
holds the highest precedence available to file-based layering:

```yaml
# argocd/applications/dev.yaml — SANITIZED IMPLEMENTATION-DERIVED EXAMPLE
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: astroshop-dev
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: astroshop-dev
  sources:
    - repoURL: https://open-telemetry.github.io/opentelemetry-helm-charts
      chart: opentelemetry-demo
      targetRevision: "0.40.10"
      helm:
        releaseName: astroshop
        valueFiles:
          - $values/base/values.yaml
          - $values/environments/dev/values.yaml
          - $values/environments/dev/images.yaml
    - repoURL: <private-gitops-repository>
      targetRevision: main
      ref: values
```

Four things are deliberately absent, and each absence is a guard rail: no glob in
`valueFiles`, so the layer order stays visible and reviewable; no `ignoreMissingValueFiles`,
so a missing layer fails the render instead of silently disappearing; no `helm.parameters`,
`helm.values` or `helm.valuesObject`, because all three outrank `valueFiles` and would open a
second override path; no `skipSchemaValidation`, so the chart's schema keeps validating the
merged values. The second source carries no `path`, so Argo CD never generates resources from
the GitOps repository itself; it supplies values only.

## 3. Pinning by digest

The upstream chart's image object is closed to `repository`, `tag`, `pullPolicy` and
`pullSecrets`, so there is no digest field. The chart joins repository and tag with a literal
colon, which means an OCI digest reference survives being split across that colon:

```yaml
# environments/dev/images.yaml — SANITIZED IMPLEMENTATION-DERIVED EXAMPLE
components:
  checkout:
    imageOverride:
      repository: "<account>.dkr.ecr.<region>.amazonaws.com/astroshop/checkout@sha256"
      tag: "<64-hex-digest>"
```

That renders as `…/astroshop/checkout@sha256:<64-hex-digest>`, so the pod pulls by digest
and the tag plays no part in identity. It is measured template behaviour of chart 0.40.10, so
a chart upgrade re-opens the question. Promotion is a merge request that edits `images.yaml`
and nothing else; its diff is exactly a digest change, reviewed and merged by the owner. The
Validation and Production-Validation image layers are intentionally empty: an environment
with no reviewed artifact identity must not be deployed. The automatic CI-to-GitOps Dev pin
that ADR-0009 describes is **not implemented**; every pin so far is a manual reviewed change.

## 4. Bootstrap and reconciliation

Argo CD reads the private repository through a deploy key that is never typed into the
cluster. The bootstrap applies, in order: the `argocd` namespace; External Secrets Operator
from a chart artifact whose SHA-256 is verified before install; a `SecretStore` that reaches
AWS Secrets Manager through EKS Pod Identity; an `ExternalSecret` that materialises the
repository credential as a Kubernetes Secret; then the Argo CD install manifest, fetched from
an immutable commit and applied only on an exact SHA-256 match. A mismatch at either pin means
stop. After the workload and observability namespaces exist, the four observability backends,
the collector and the workload Applications are introduced, in that order.

Sync is deliberately manual: the Applications carry no `syncPolicy`, so nothing self-heals or
prunes, and every reconciliation in a runtime window is an authorized step. The `default`
AppProject is a declared limitation. What this produced on EKS, and the digest read back from
the running containers, is in [Runtime Validation](../validation/runtime-validation.md).

## 5. Fault and restore as desired-state changes

Recovery uses the same mechanism as delivery. Before a window, the desired state is frozen at
an anchor commit. A fault is one semantic change on a branch from that anchor, merged inside
the window through the normal merge request; the restore is the exact reverse, merged the same
way. This is the fault that drove the alerting window, thirteen lines in one file:

```diff
# environments/dev/values.yaml — SANITIZED IMPLEMENTATION-DERIVED EXAMPLE
-  quote: {enabled: true}
+  quote:
+    enabled: true
+    livenessProbe:
+      httpGet: {path: /rw-liveness-fault, port: 8080}
+      initialDelaySeconds: 5
+      periodSeconds: 5
+      timeoutSeconds: 1
+      failureThreshold: 1
```

A liveness probe against a path the service never serves makes the kubelet restart the
container on every probe cycle, which the alert rule then observes. The restore removes the
block. Proof that recovery is complete is Git tree equality: the restore merge's tree hash
equals the anchor's tree hash before the recovery leg is accepted, and it did (`82224ce7…` on
both, 2026-09-13).
