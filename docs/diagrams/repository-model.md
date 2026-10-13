# Repository Model

Three repositories carry the platform, each with one responsibility and one authoritative
host ([ADR-0009](../decisions/0009-define-the-software-delivery-model.md)). The GitHub copy of
the workload repository is a one-way mirror kept for browsing: merge requests, pipelines and
the authoritative history stay on GitLab, and nothing is developed in the mirror.

```mermaid
flowchart TB
    subgraph PUBLIC
        direction LR
        REF["GitHub: cloud-platform-reference<br/>AUTHORITATIVE platform repository<br/>Terraform, decisions, documentation. Start here"]
        WL["GitLab: cloud-platform-workload<br/>AUTHORITATIVE workload source<br/>merge requests and CI"]
        WLM["GitHub: cloud-platform-workload<br/>MIRROR, read-only<br/>same commits, no pull requests, no Actions"]
    end
    subgraph PRIVATE
        direction LR
        GO["GitLab: cloud-platform-gitops<br/>AUTHORITATIVE desired state<br/>Argo CD values and image digests. Not mirrored"]
        OPS["Owner workspace<br/>raw evidence and operator tooling<br/>never published"]
    end
    WL -->|"one-way push mirror"| WLM
    WL -->|"published image digests are pinned by merge request in"| GO
    REF -.->|"documents and links to"| WL
    REF -.->|"documents the model implemented in"| GO
```

Solid arrows carry Git objects or artifact identity in one direction. Dotted arrows are
documentation links. The mirror is never ahead of GitLab and shows nothing that has not been
pushed there.
