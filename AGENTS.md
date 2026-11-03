# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, Copilot, etc.) working
in this repository. Read it before making changes, and add what you learn here as
you go. General preferences (attribution, git workflow, comment style, how to
maintain this file) live in the owner's global `~/.config/agents/AGENTS.md`.

## What this repo is

GitOps source of truth for a personal homelab: two k3s clusters and everything
that runs on them.

| Cluster | Hardware | How it's built | How apps get there |
| --- | --- | --- | --- |
| **home** | `k3s-01` ThinkCentre M910q (x86, i5-7500T, 16GB, Intel iGPU, NVMe) as server; `k3s-02`–`k3s-05` Raspberry Pi 4b (arm64, 4GB, SD cards) as workers | Ansible (`ansible/`) | ArgoCD running on this cluster |
| **oci** | Oracle Cloud Always Free ARM: `oci-k3s-server` + `oci-k3s-worker-1` (2 OCPU / 12GB / 100GB each) | Terraform (`terraform/`, Terraform Cloud workspace `alfiemellor/infrastructure`) with cloud-init bootstrapping k3s | The **home** ArgoCD, over Tailscale |

Supporting infrastructure outside the clusters: TrueNAS at `192.168.1.100`
(NFS media and Longhorn backup target), Cloudflare (DNS for `mellor.dev`,
tunnel, Access), Tailscale (tailnet), 1Password (all secrets).

Public domain for everything is `mellor.dev`. Timezone is `Europe/London`;
cron schedules in manifests are UTC.

## Layout

```
apps/
  argocd/clusters/home.yaml     ApplicationSet: one Argo app per apps/overlays/home/* dir
  base/<area>/[<app>/]          The actual manifests: plain YAML and/or a Kustomize helmCharts entry + values.yaml
  overlays/home/<namespace>/    What the home cluster runs; a kustomization listing ../../../base/... paths
  overlays/oci/<namespace>/     What the OCI cluster runs (same pattern)
ansible/
  group_vars/all.yml            k3s version, server flags, node labels
  inventory.example.yaml        Template for the gitignored inventory.yaml (home nodes)
  inventory.oci.yaml            OCI nodes, by Tailscale hostname (kept separate on purpose)
  playbooks/                    bootstrap, k3s deploy/upgrade/uninstall, OS updates, Longhorn prereqs, tuning
terraform/                      OCI compartment, VCN, and instances (modules/{compartment,network,instance})
.renovaterc.json                Dependency update rules (images + Helm charts under apps/)
```

### How ArgoCD wires it together

- `apps/argocd/clusters/home.yaml` (ApplicationSet `home-apps`) generates one
  Application per directory in `apps/overlays/home/*`. **The directory name is
  both the Argo app name and the destination namespace.**
- `apps/overlays/home/argocd/oci-apps.yaml` (ApplicationSet `oci-apps`) does the
  same for `apps/overlays/oci/*`, naming apps `oci-<dir>` and targeting the
  cluster registered by `oci-cluster.yaml` (API reached via a Tailscale egress
  Service; credentials from 1Password).
- All apps auto-sync with `prune: true`, `selfHeal: true`, `ServerSideApply=true`,
  `CreateNamespace=true`. **Merging to `main` deploys.** There is no staging.
- Helm charts are rendered by Kustomize (`helmCharts:` in a base
  `kustomization.yaml`), not by Argo Helm sources.

### Adding an app

1. Create `apps/base/<area>/<app>/` with a `kustomization.yaml` (set `namespace:`
   to the target namespace) and its manifests, or a `helmCharts:` entry pinned to
   an exact `version` with a sibling `values.yaml`.
2. If `<area>` groups several apps, list it in `apps/base/<area>/kustomization.yaml`.
3. Reference it from the overlay for the cluster it should run on
   (`apps/overlays/<cluster>/<namespace>/kustomization.yaml`). A new overlay
   directory creates a new Argo app and namespace automatically.
4. Render it locally before committing (see [Validating changes](#validating-changes)).

## Design choices and conventions

### GitOps only
- Everything in-cluster goes through ArgoCD. Do not `kubectl apply/edit/delete`
  to change state; change git instead. Read-only `kubectl`/Argo inspection is fine.
- Nodes are changed only through Terraform (OCI) or committed Ansible playbooks.
  **No ad-hoc SSH commands on nodes and no manual steps handed to the user.** For
  node checks, use Ansible (`--check --diff`, or ad-hoc `ansible -m` modules
  against the inventory).

### Manifests
- One resource kind per file, named by kind: `deployment.yaml`, `service.yaml`,
  `ingress.yaml`, `pvc.yaml`, `networkpolicy.yaml`, `onepassworditem.yaml`,
  `postgres.yaml`, `values.yaml`.
- Labels: hand-written apps use `app: <name>`; chart-based apps use the chart's
  `app.kubernetes.io/*` labels.
- Single-replica stateful apps use `strategy: Recreate` (RWO volumes).
- Images: prefer a tag pinned with a digest (`image:tag@sha256:...`), which
  Renovate keeps current. Some older apps still use `:latest`.
- Manifests carry a lot of *why* comments, often at the top of the file; keep
  them accurate when you change the thing they explain.

### Exposure / ingress
Pick the ingress class by who should reach the app:

| Class | Cluster | Reachable from | Notes |
| --- | --- | --- | --- |
| `internal` (default) | home, oci | Tailnet only (Tailscale LoadBalancer) | cert-manager `letsencrypt` ClusterIssuer + `tls:` block; external-dns publishes `<host>.mellor.dev` to the tailnet IP |
| `external` | home | Internet via LAN MetalLB IP | Add `external-dns.alpha.kubernetes.io/target: direct.mellor.dev` (kept current by `cloudflare-ddns-direct`); cert-manager TLS |
| `cloudflare-tunnel` | home | Internet via Cloudflare Tunnel | No `tls:` block (TLS ends at Cloudflare). DNS comes from the tunnel controller, not external-dns. **Cloudflare Access must cover the hostname before the Ingress syncs**, unless the app's own login is SSO-only through an Access for SaaS app (TREK; see `OIDC_ONLY` in `apps/base/travel/trek/deployment.yaml` for why the two don't stack). Pair with a restrictive NetworkPolicy (see `apps/base/travel/trek/networkpolicy.yaml`) |

external-dns still reads the legacy `external-dns.alpha.kubernetes.io/` annotation
prefix (enabled via `--enable-legacy-annotation-prefix`).

Internet-exposed or third-party-image apps get a NetworkPolicy that allows only
what they need and blocks private ranges (`10/8`, `172.16/12`, `192.168/16`,
`169.254/16`, `100.64/10`) on egress.

### Secrets
- Secrets come from 1Password via the 1Password operator: a `OnePasswordItem` with `itemPath: "vaults/Kubernetes/items/<item>"`
  becomes a Secret whose keys are the item's field labels.
- Document the required field names in a comment on the `OnePasswordItem`
  (see `apps/base/travel/trek/onepassworditem.yaml`). Creating the item in
  1Password is a step for the user; call it out in the PR.

### Storage
- **Longhorn** is the storage for app state on both clusters (`storageClassName:
  longhorn`; it is the default class on OCI). Home Longhorn backs up to TrueNAS
  over NFS; OCI Longhorn backs up to TrueNAS over the tailnet. TrueNAS then
  syncs to Google Drive.
- Every Longhorn volume is backed up daily/weekly by default
  (`apps/base/longhorn*/recurringjobs.yaml`). Opt **out** scratch/regenerable
  data by labelling the PVC with both
  `recurring-job.longhorn.io/source: enabled` and
  `recurring-job-group.longhorn.io/no-backup: enabled`.
- `longhorn-local` (1 replica, `strict-local`) keeps heavy-write data (Loki,
  Prometheus) on `k3s-01`'s NVMe and off the Pi SD cards.
- Bulk media is a static NFS PV/PVC (`storageClassName: ""`, `Retain`) pointing
  at TrueNAS.
- Postgres uses CloudNativePG (`postgres.yaml`, `kind: Cluster`): one instance on
  Longhorn, `enablePDB: false` so it doesn't block node drains.
- Both clusters must run the **same Longhorn version** (`apps/base/longhorn` and
  `apps/base/longhorn-oci`); Longhorn upgrades go one minor version at a time.
- k3s is installed with `--disable local-storage` at home; `local-path` exists
  only on OCI.

### Scheduling
- Node labels (from `ansible/group_vars/all.yml`): `arch=x86` / `role=master` on
  `k3s-01`, `arch=arm64` / `role=worker` on the Pis, plus
  `intel.feature.node.kubernetes.io/gpu=true` on `k3s-01`.
- Anything that needs x86 or the Intel GPU (`gpu.intel.com/i915`, e.g. Plex) pins
  to `arch: x86`. Check that images are multi-arch before letting them land on the
  Pis. `k3s-01` is the only big node, so watch its CPU/memory requests.

### Dependencies (Renovate)
- Renovate scans `apps/base/**` and `apps/overlays/**` weekly (Monday before 03:00
  UTC); container images are grouped into one "app container images" PR.
  `ansible/` and `terraform/` are ignored.
- Longhorn is held `< 1.13.0` until the home control plane runs Kubernetes 1.34+
  (tracked as Windshift HL-15). Update the rule in `.renovaterc.json` when that
  changes.

## Gotchas learned the hard way

- **PVC prune deadlock:** never remove a PVC in the same commit that stops a
  workload mounting it. Argo prunes the PVC first, the `pvc-protection`
  finalizer holds it while the old pod still mounts it, and the sync never gets
  to the Deployment change. Split into two PRs (stop mounting, then remove the
  PVC), or use `PruneLast=true` / a later sync wave.
- **Storage migrations** are done in staged PRs: add the new volume and copy
  data, switch over, then remove the old PVC (see history around #128–#134).
- **CRD ordering on OCI:** OCI apps use `SkipDryRunOnMissingResource=true` plus
  sync retries because CRDs (OnePasswordItem, ClusterIssuer, ServiceMonitor)
  arrive from other apps.
- **PVCs created by StatefulSet templates** can't be labelled through the chart;
  `apps/base/monitoring/longhorn-backup-exclusions` re-declares them with
  `Prune=false,Delete=false` just to add labels. Keep their sizes in step with
  the live PVCs.
- **Two `inventory` files on purpose:** `inventory.yaml` (home, gitignored) is used
  by playbooks targeting `hosts: all`; OCI nodes live in `inventory.oci.yaml` so
  those playbooks never touch them. Pass `-i inventory.oci.yaml` explicitly.
- `ansible/group_vars/all.yml:k3s_version` is the **target** version for
  `k3s-upgrade.yaml`, not necessarily what is running. Check the cluster before
  assuming a Kubernetes version.
- OCI cannot resolve `*.ts.net` from CoreDNS; use tailnet IPs in in-cluster config
  that must reach home services.
- Home pods can't reach tailnet IPs either (the nodes aren't on the tailnet;
  only the Tailscale operator's proxies are), so e.g. Homarr can't status-ping
  OCI apps.
- Homarr's boards, apps and integrations live only in its SQLite database
  (managed in the UI, not git), so the Longhorn backup of `homarr-database` is
  the only copy. Keep it backed up.
- Kustomize leaves `metadata.namespace` unset on Helm output when the chart's
  templates don't set it (Homarr's don't). Argo's destination namespace covers
  it, but don't expect `namespace:` in the kustomization to show up in a
  local render.

## Validating changes

There is no CI on manifests, so render locally before committing:

```sh
kustomize build --enable-helm apps/overlays/home/<namespace>   # or apps/overlays/oci/<namespace>
```

`--enable-helm` pulls charts into `apps/**/charts/`, which is gitignored; never
commit it. Also useful:

- `ansible-playbook -i <inventory> playbooks/<file>.yaml --check --diff` (from `ansible/`)
- `terraform fmt` / `terraform validate` (plans and applies run in Terraform Cloud)
- Read-only ArgoCD inspection (app status, events, resource trees) to confirm a
  change synced after merge.

## Git and PR workflow

General git, commit, and attribution rules are in the global file. Specific to
this repo:

- PRs are squash-merged into `main`, and merging deploys. If a PR must wait for
  something else to sync first, say so in the body.
- Renovate's PRs use `chore(deps): ...`.
- The repo is public, so the no-AI-attribution rule matters doubly here.
- Work tracking lives in **Windshift** (`windshift.mellor.dev`, workspace
  "Homelab", key `HL`), not Plane. Reference tickets as `Windshift HL-<n>`.
