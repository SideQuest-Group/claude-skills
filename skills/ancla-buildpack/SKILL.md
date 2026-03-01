---
name: ancla-buildpack
description: Sets up and configures Buildpack-based builds for Ancla services. Configures CNB builder, handles build-time env vars, and troubleshoots build failures (pack CLI and kpack). Use when setting up a buildpack service, switching from Dockerfile to buildpack, debugging buildpack build failures, or when the user mentions buildpacks, CNB, Paketo, pack CLI, or kpack in the context of Ancla.
---

# Ancla Buildpack Setup

Configures services to build with Cloud Native Buildpacks (CNB) instead of Dockerfiles. Buildpacks auto-detect language/framework and produce OCI images without a Dockerfile. Processes are auto-discovered from the built image — no Procfile required.

## When to Use Buildpacks vs Dockerfiles

| Use Buildpack | Use Dockerfile |
|---|---|
| Standard app (Python, Node, Go, Java, Ruby) | Custom system packages or non-standard base |
| Quick start — no Dockerfile needed | Multi-stage builds or specific layer control |
| Paketo builder supports the stack | Need to pin exact base image or OS version |
| Want automatic security patching via rebase | Need build-time `RUN` commands |

## How Process Discovery Works

Buildpack builds do **not** require a Procfile. After the image is built and pushed, Ancla inspects it to discover processes:

1. **CNB metadata labels** — reads `io.buildpacks.build.metadata` (or `io.buildpacks.lifecycle.metadata`) from the image config. These contain a `processes` list with types like `web`, `worker`, etc.
2. **CMD/ENTRYPOINT fallback** — if no CNB labels are found, extracts the image's `CMD`/`ENTRYPOINT` and maps it to a `web` process.

This means any app that a Paketo buildpack can detect will automatically get the right process types without any configuration.

## Setup Workflow

### 1. Set Build Strategy

**Via UI:** Service Settings > Build Strategy > select "Buildpack" > Save Strategy

**Via API:**
```
PATCH /api/v1/workspaces/{ws}/projects/{proj}/envs/{env}/services/{svc}
{"build_strategy": "buildpack"}
```

### 2. Auto-Detection

The detect endpoint probes GitHub for Dockerfiles and recommends a strategy:

```
POST /api/v1/.../services/{svc}/detect?apply=true
```

Priority: `Dockerfile.ancla` > `Dockerfile` > buildpack fallback. If no Dockerfile is found, detection recommends `"buildpack"`.

### 3. Build-Time Environment Variables

Buildpack services inject build-time variables via `--env K=V` flags to `pack build` (or `spec.env` for kpack). Set them in the service's Config tab as build-time variables.

## Build Backends

Ancla supports two buildpack backends, selected via `ANCLA_BUILDPACK_BACKEND`:

| Backend | How it works | When to use |
|---|---|---|
| `pack` (default) | Runs `pack build` in a K8s Job with git-clone init container | Simple setup, Docker socket available |
| `kpack` | Creates a kpack `Build` custom resource (K8s-native CNB) | No Docker socket needed, better security, K8s-native |

**kpack** requires the kpack controller installed in the cluster and `KUBERNETES_ENABLED=true`. It creates ephemeral Build CRs, ServiceAccounts, and annotated Secrets, then polls the CR status until completion.

## How Builds Execute

See [BUILD-PIPELINE.md](BUILD-PIPELINE.md) for the full pipeline spec, caching strategy, and local dev path.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common buildpack failures and fixes.

## Configuration

Override via environment variables (all use `ANCLA_` prefix):

| Env Var | Default | Purpose |
|---|---|---|
| `ANCLA_BUILDPACK_BUILDER_IMAGE` | `paketobuildpacks/builder-jammy-full:latest` | CNB builder image |
| `ANCLA_BUILDPACK_PACK_IMAGE` | `buildpacksio/pack:latest` | Pack CLI image (pack backend only) |
| `ANCLA_BUILDPACK_BACKEND` | `pack` | Backend: `"pack"` or `"kpack"` |
| `ANCLA_KPACK_CLUSTER_BUILDER` | `default` | kpack ClusterBuilder name |
| `ANCLA_KPACK_NAMESPACE` | `default` | Namespace for kpack Build CRs |

The default Paketo Jammy Full builder supports: Python, Node.js, Go, Java, Ruby, .NET, PHP, Nginx, httpd.

## Bun Support

Paketo and Heroku's Node.js buildpacks don't support Bun. For apps using `bun.lock`, use our CNB buildpack:

- **Repo:** https://github.com/SideQuest-Group/cnb-bun
- **Quick link:** https://get.ancla.dev/cnb-bun

It detects `bun.lock`/`bun.lockb`, installs Bun, runs `bun install --frozen-lockfile`, and executes build scripts. Designed to run alongside other buildpacks (e.g. before `heroku/python` in a dual-stack app).

Use it via `project.toml` in the app repo:

```toml
[_]
schema-version = "0.2"

[[io.buildpacks.group]]
uri = "https://github.com/SideQuest-Group/cnb-bun"

[[io.buildpacks.group]]
id = "heroku/python"
```

Or pass it directly to pack CLI: `--buildpack https://github.com/SideQuest-Group/cnb-bun`

Pin bun version with a `.bun-version` file or `BUN_VERSION` build-time env var.

## Notes

- **No Procfile support** — Ancla does not use Procfiles. Processes are auto-discovered from the built image (CNB metadata or CMD/ENTRYPOINT).
- **Registry auth key** — the pack CLI path uses bare hostname (e.g. `localhost:5001`) for the docker config auth key, not `scheme://host/v2/`.
