# Repository Model

Three repositories carry the platform, each with one responsibility and one authoritative
host ([ADR-0009](../decisions/0009-define-the-software-delivery-model.md)). GitLab holds the
authoritative workload repository, and merge requests, pipelines and history stay there. The
GitHub copy is a one-way presentation mirror that GitLab pushes to, with GitHub Actions
disabled. Not developing in the mirror is an owner working rule, not an enforced permission
boundary.

```mermaid
flowchart TB
    subgraph PUBLIC
        direction LR
        REF["GitHub: cloud-platform-reference<br/>AUTHORITATIVE platform repository<br/>Terraform, decisions, documentation. Start here"]
        WL["GitLab: cloud-platform-workload<br/>AUTHORITATIVE workload source<br/>merge requests and CI"]
        WLM["GitHub: cloud-platform-workload<br/>PRESENTATION MIRROR<br/>pushed from GitLab, Actions disabled"]
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
documentation links. Mirror updates can lag behind GitLab, and a branch deleted on GitLab can
remain on GitHub.
