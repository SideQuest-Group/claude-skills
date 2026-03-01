# Buildpack Build Pipeline

## Pack Backend: K8s Job Structure

When `ANCLA_BUILDPACK_BACKEND=pack` (default) and `KUBERNETES_ENABLED=true`, a buildpack build creates a K8s Job named `packbuild-{job_id}`:

### Init Container — Git Clone

```yaml
image: alpine/git:latest
command: ["git", "clone", "--depth=1", "--branch", "{ref}", "{repo_url}", "/workspace"]
```

A GitHub access token secret (`github-access-token-{job_id}`) is mounted for private repos. The clone URL format: `https://x-access-token:{token}@github.com/{owner}/{repo}.git`

### Main Container — Pack Build

```yaml
image: buildpacksio/pack:latest  # ANCLA_BUILDPACK_PACK_IMAGE
args:
  - build
  - "{registry}/{repo}:image-{version}"
  - --builder
  - "paketobuildpacks/builder-jammy-full:latest"  # ANCLA_BUILDPACK_BUILDER_IMAGE
  - --publish
  - --path
  - "/workspace/{subdirectory}"  # or just /workspace if no subdirectory
  - --cache-image
  - "{registry}/{repo}:pack-buildcache"
  - --env
  - "KEY=VALUE"  # repeated for each build-time var
```

Docker registry auth is mounted at `/home/cnb/.docker/config.json` (CNB convention, not `/root/.docker/`). The auth key in the docker config uses the bare registry hostname (e.g. `localhost:5001`), not `scheme://host/v2/`.

### Job Config

- `activeDeadlineSeconds: 1800` (30 minute timeout)
- `backoffLimit: 0` (no retries)
- Cleanup: secrets and job are deleted after completion

## kpack Backend: Build CR Structure

When `ANCLA_BUILDPACK_BACKEND=kpack` and `KUBERNETES_ENABLED=true`, a buildpack build creates a kpack `Build` custom resource instead of a K8s Job.

### Resources Created

For each build, four ephemeral resources are created in the `ANCLA_KPACK_NAMESPACE`:

1. **Registry secret** (`kpack-registry-{job_id}`) — `kubernetes.io/dockerconfigjson` type, annotated with `kpack.io/docker: {registry}` so the kpack controller can match it to the target registry.
2. **Git secret** (`kpack-git-{job_id}`) — `kubernetes.io/basic-auth` type, annotated with `kpack.io/git: https://github.com`. Only created when an access token is available.
3. **ServiceAccount** (`kpack-build-{job_id}`) — references both secrets. The kpack controller uses this SA to pull source and push images.
4. **Build CR** (`ancla-build-{job_id}`) — the actual build definition.

### Build CR Spec

```yaml
apiVersion: kpack.io/v1alpha2
kind: Build
metadata:
  name: ancla-build-{job_id}
  labels:
    workspace: {ws_slug}
    project: {proj_slug}
    service: {svc_slug}
    process: build
    build_id: {job_id}
    ancla.io/managed-by: ancla
spec:
  tags: ["{registry}/{repo}:image-{version}"]
  builder:
    image: "{builder_image}"  # ANCLA_BUILDPACK_BUILDER_IMAGE
  serviceAccountName: kpack-build-{job_id}
  source:
    git:
      url: "https://github.com/{owner}/{repo}.git"
      revision: "{commit_sha}"
    subPath: "{subdirectory}"  # only if service has subdirectory
  cache:
    registry:
      tag: "{registry}/{repo}:pack-buildcache"
  env:  # only if build-time vars exist
    - name: KEY
      value: VALUE
```

### Polling and Completion

The build is polled every 3 seconds (up to 30 minute timeout). The kpack controller sets a `Succeeded` condition on the Build CR:

- `status: "True"` → build succeeded
- `status: "False"` → build failed (reason + message extracted for error)
- `status: "Unknown"` → still in progress

After completion, logs are fetched from the build pod (found via `kpack.io/build={name}` label or ownerReference UID). All init and main container logs are captured.

### Cleanup

All ephemeral resources (Build CR, ServiceAccount, secrets) are deleted in a `finally` block, tolerant of 404s.

## Process Discovery

After a successful build (either backend), Ancla inspects the pushed image via the registry V2 API:

1. Fetch the image manifest to get the config digest
2. Fetch the config blob to read labels
3. Parse CNB labels (`io.buildpacks.build.metadata` first, then `io.buildpacks.lifecycle.metadata`) for a `processes` list
4. If no CNB processes found, extract `CMD`/`ENTRYPOINT` as a `web` process
5. Returns `(processes, source_kind)` where `source_kind` is `"cnb_metadata"` or `"image_cmd"`

If inspection fails entirely, falls back to `{"web": {"cmd": "", "env": []}}`.

## Caching

- **Cache image**: `{registry}/{repo}:pack-buildcache` — stored in the container registry
- Separate from Dockerfile cache (`image-buildcache` tag), so switching strategies is safe
- Cache is per-service, keyed by registry + repo name
- Both pack and kpack backends use the same cache tag format

## Local Dev Path

When `BUILDKIT_ENABLED=false` (local dev), the `FakeBuildStrategy` runs instead — it doesn't actually invoke `pack`. To test buildpack builds locally:

1. Install `pack` CLI: `brew install buildpacks/tap/pack`
2. Run manually: `pack build myapp --builder paketobuildpacks/builder-jammy-full --path .`

## Release Build

After the buildpack produces an image, the **release build** (always BuildKit) layers envconsul configuration on top. This applies identically to both Dockerfile and Buildpack images:

```
FROM {registry}/{repo}:image-{version}
# + envconsul binary and config
```

The release image is what actually runs on K8s.

## Code References

| File | Purpose |
|---|---|
| `ancla/tasks/build/_buildpack.py` | Pack CLI BuildpackBuildStrategy (K8s Job + local subprocess) |
| `ancla/tasks/build/_buildpack_kpack.py` | KpackBuildStrategy (kpack Build CR) |
| `ancla/tasks/build/_image_inspector.py` | OCI image inspection, CNB label parsing, CMD/ENTRYPOINT fallback |
| `ancla/tasks/build/_orchestrator.py` | `run_build()` entry point, `run_release()` |
| `ancla/tasks/build/_selector.py` | Strategy dispatch (`get_build_strategy`) — routes to pack, kpack, or fake |
| `ancla/tasks/build/_detector.py` | Auto-detection: Dockerfile.ancla > Dockerfile > buildpack fallback |
| `ancla/tasks/build/_github.py` | GitHub file fetching and token resolution |
| `ancla/server/config/base.py` | `BUILDPACK_*`, `KPACK_*` config fields |
