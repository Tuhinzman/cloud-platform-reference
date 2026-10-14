# Repository Model

Three engineering repositories carry the platform, each with one responsibility and one
authoritative host ([ADR-0009](../decisions/0009-define-the-software-delivery-model.md)). The
owner workspace is drawn apart from them: it is local only and is not an engineering repository.

```mermaid
---
config:
  theme: base
  themeVariables:
    lineColor: "#475569"
    edgeLabelBackground: "#ffffff"
    primaryTextColor: "#0f172a"
  flowchart:
    wrappingWidth: 320
---
flowchart LR
    subgraph PUBLIC["PUBLIC"]
        REF["cloud-platform-reference<br/>GitHub · authoritative"]
        WL["cloud-platform-workload<br/>GitLab · authoritative"]
        WLM["cloud-platform-workload<br/>GitHub · presentation mirror"]
    end
    subgraph PRIVATE["PRIVATE"]
        GO["cloud-platform-gitops<br/>GitLab · authoritative"]
        subgraph LOCAL["LOCAL ONLY"]
            OWN["owner workspace<br/>no remote · never published"]
        end
    end
    REF -.->|"documents"| WL
    WL -->|"one-way push mirror"| WLM
    WL -->|"image digest via MR"| GO
    OWN ~~~ GO

    classDef repo fill:#ffffff,stroke:#475569,stroke-width:2px,color:#0f172a
    classDef gitops fill:#ffffff,stroke:#7c3aed,stroke-width:2px,color:#0f172a
    classDef mirror fill:#f8fafc,stroke:#64748b,stroke-width:1.5px,stroke-dasharray:6 4,color:#334155
    classDef local fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,stroke-dasharray:3 3,color:#334155
    class REF,WL repo
    class GO gitops
    class WLM mirror
    class OWN local
    style PUBLIC fill:#f8fafc,stroke:#475569,stroke-dasharray:6 4,color:#0f172a
    style PRIVATE fill:#f1f5f9,stroke:#475569,stroke-dasharray:6 4,color:#0f172a
    style LOCAL fill:#e2e8f0,stroke:#94a3b8,stroke-dasharray:3 3,color:#334155
```

- **cloud-platform-reference** (GitHub): architecture, decisions, Terraform and documentation.
  Start here. It documents the workload repository and the model the GitOps repository
  implements, and links to both.
- **cloud-platform-workload** (GitLab): the workload source, container builds and per-service CI.
  Merge requests, pipelines and history stay on GitLab.
- **The GitHub copy of cloud-platform-workload** is a one-way presentation mirror that GitLab
  pushes to, with GitHub Actions disabled. Not developing in the mirror is an owner working rule,
  not an enforced permission boundary. Mirror updates can lag behind GitLab, and a branch deleted
  on GitLab can remain on GitHub.
- **cloud-platform-gitops** (GitLab, private): the desired state Argo CD reconciles, with its
  values and the image digest each environment runs. A published image digest is pinned there by
  merge request. It is not mirrored.
- **The owner workspace** holds raw evidence and operator tooling. It has no remote and is never
  published.

Solid arrows carry Git objects or artifact identity in one direction, and the dotted arrow is a
documentation link. A solid slate border marks an authoritative repository, purple marks the
GitOps desired state, a dashed border marks the mirror and a dotted grey border marks the
local-only workspace.
