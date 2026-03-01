# Buildpack Troubleshooting

## Common Failures

### Pack build times out (30 min deadline)

**Cause:** Large dependencies, no cache, or slow registry.

**Fixes:**
- First build is always slowest (cold cache). Subsequent builds use `--cache-image`
- Check if the builder image supports the language version in use
- For Python: ensure `requirements.txt` or `setup.py`/`pyproject.toml` exists at the path root
- For Node: ensure `package.json` exists

### "No buildpack groups passed detection"

**Cause:** The Paketo builder couldn't detect the app's language/framework.

**Fixes:**
- Verify the app has the expected manifest file at the build path:
  - Python: `requirements.txt`, `setup.py`, `pyproject.toml`, or `Pipfile`
  - Node.js: `package.json`
  - Go: `go.mod`
  - Java: `pom.xml` or `build.gradle`
  - Ruby: `Gemfile`
- If using a subdirectory, ensure `--path` resolves to where these files live
- If the framework isn't supported by Paketo, switch to Dockerfile strategy

### No processes discovered from image

**Cause:** The image was built but Ancla couldn't extract process types.

**Check:**
- CNB metadata label `io.buildpacks.build.metadata` may be missing (unusual for Paketo builds)
- Image may not have a `CMD` or `ENTRYPOINT` either
- Ancla falls back to `{"web": {"cmd": "", "env": []}}` — the deploy will still proceed but the process command will be empty
- Verify the buildpack actually produced a runnable image (check build logs for warnings)

### GitHub clone fails in init container

**Cause:** Token expired, repo doesn't exist, or branch/SHA not found.

**Check:**
- `effective_installation_id` is set on the service (or via RepositoryConnection)
- The GitHub App has access to the repository
- The commit SHA or branch ref exists in the repo

## Pack Backend Issues

### Registry auth failure in K8s Job

**Cause:** Docker config secret not mounted correctly, or CNB user can't read it.

**Check:**
- Secret is mounted at `/home/cnb/.docker/config.json` (NOT `/root/.docker/`)
- The auth key in the docker config JSON uses the **bare hostname** (e.g. `localhost:5001`), not `https://localhost:5001/v2/`
- The registry credentials in the secret are valid
- The CNB user (uid 1000) has read access

## kpack Backend Issues

### kpack build stuck in "Unknown" status

**Cause:** The kpack controller isn't running or can't process the Build CR.

**Check:**
- kpack controller pods are running: `kubectl get pods -n kpack`
- The `ANCLA_KPACK_NAMESPACE` matches where Build CRs are created
- RBAC allows the kpack controller to manage Build CRs, pods, and secrets
- Check kpack controller logs: `kubectl logs -n kpack -l app=kpack-controller`

### kpack registry auth failure

**Cause:** The annotated secret isn't being picked up by the kpack controller.

**Check:**
- Registry secret has annotation `kpack.io/docker: {registry_hostname}` — the value must match the registry used in `spec.tags`
- Secret type is `kubernetes.io/dockerconfigjson`
- ServiceAccount references the secret
- For git access: git secret has annotation `kpack.io/git: https://github.com` and type `kubernetes.io/basic-auth`

### kpack build failed with reason in CR

**Cause:** The Build CR's `Succeeded` condition has `status: "False"` with a reason.

**Check:**
- Read the condition message: it usually contains the buildpack or lifecycle error
- Common reasons: `BuildFailed` (buildpack error), `PodFailed` (infra issue)
- Fetch pod logs for details — the build pod is labeled `kpack.io/build={build_name}`

### kpack build timed out

**Cause:** Build exceeded the 30 minute polling deadline.

**Check:**
- Same causes as pack timeout (large deps, cold cache, slow registry)
- Additionally: kpack controller may be overloaded or the build pod may be stuck in `Pending` (resource constraints)
- Check pod status: `kubectl get pods -n {KPACK_NAMESPACE} -l kpack.io/build=ancla-build-{job_id}`

## Switching Strategies

Switching between Dockerfile and Buildpack is safe:
- Cache images use different tags (`image-buildcache` vs `pack-buildcache`)
- No cleanup needed — just change `build_strategy` on the service
- Next build will use the new strategy automatically

Switching between pack and kpack backends is also safe — just change `ANCLA_BUILDPACK_BACKEND`. Both produce the same image format and use the same cache tag.

## Language-Specific Notes

### Python
- Paketo looks for `requirements.txt` at the build path root
- `pyproject.toml` with `[project]` section also works
- Set `BP_CPYTHON_VERSION` build-time env var to pin Python version

### Node.js
- Paketo looks for `package.json`
- Set `BP_NODE_VERSION` to pin Node version
- `npm start` or the `start` script in `package.json` is used as the default web process

### Go
- Paketo looks for `go.mod`
- Builds the main package by default
- Set `BP_GO_TARGETS` to specify build targets

### Java
- Paketo supports Maven (`pom.xml`) and Gradle (`build.gradle`)
- Set `BP_JVM_VERSION` to pin Java version
