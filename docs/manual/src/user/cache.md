<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# A cache for your (internal) CI/CD pipelines

This document describes how to configure a **Nix binary cache** in a CI/CD pipeline so that build results can be reused across runs and across machines.
Using a cache dramatically reduces build times and load on your CI infrastructure when building Sécurix-related artifacts (ISOs, system configurations, etc.)

The examples are intentionally **CI-agnostic**. Where GitHub Actions–specific tooling is referenced, we explain how to replace it in other CI systems.

## High-level pipeline flow

A CI pipeline using a Nix cache usually follows these steps:

1. Check out the repository
2. Install Nix (Sécurix upstream is developed and tested using https://lix.systems/).
3. Configure cache access (substituters + credentials)
4. Run `nix-build`, `nix develop`, or `nix build`
5. Upload build results to the cache

Each of these steps is described below.

> Note: Garbage collection is not covered in this document. After a while, your S3 cache will accumulate useless Nix store paths.
> You can run a scheduled pipeline to expire objects based on date or liveness using on-the-shelf S3 tooling.

## Step 1: Check out the repository

Your CI system must fetch the source code before running Nix commands.

No Nix-specific configuration is required here.

## Step 2: Install Nix

A Nix interpreter must be installed on the CI runner.

### Requirements

* Linux or macOS
* Root or sudo access (unless using user-mode Nix which is not recommended)

### Generic installation options

You can install Lix using (Linux example):

```sh
curl -L https://install.lix.systems/lix/lix-installer-x86_64-linux | sh
```

After installation, ensure that:

```sh
nix --version
```

works in subsequent CI steps.

### Remarks

Many CI systems offer reusable workflows or templates to install Nix.
These often:

- Preconfigure `nix.conf` for `nixpkgs` inputs
- Inject forge tokens (GitHub, GitLab, etc.) to avoid API rate limits
- Enable optional features such as KVM acceleration

If you are using GitHub Actions, we recommend
<https://github.com/samueldr/lix-gha-installer-action>, which is fast, slim,
and easy to audit. Its logic can be ported to other CI systems if needed.

## Step 3: Configure the binary cache

This is the most important, and often the most complex, step, depending on your needs.

### Configure substituters

A substituter tells Nix where to download cached artifacts from.

Example substituter configuration:

```
s3://oss-securix
```

With additional parameters:

* `endpoint`: custom S3-compatible endpoint
* `region`: object storage region
* `compression`: artifact compression format. We recommend `zstd` over `xz`:
  `zstd` offers much faster compression and decompression with a reasonable
  size trade-off. Prefer `xz` only if storage or bandwidth is the primary
  constraint.
* `parallel-compression`: speed optimization for `xz` or `zstd`

These settings can be applied via:

* `nix.conf`
* Environment variables
* CLI flags

Example `nix.conf` snippet:

```conf
substituters = https://cache.nixos.org s3://oss-securix?endpoint=https://s3.gra.io.cloud.ovh.net&region=gra
trusted-public-keys = oss-securix-1:PUBLIC_KEY_HERE
```

## Step 4: Configure secrets

To upload artifacts to a cache, Nix must **sign** them and have write access to the S3 object store.

### Required secrets

Store the following as CI secrets:

* **Nix signing private key**: can be generated via `nix key generate-secret`
* **Object storage access key**: your S3 provider should give you that information.
* **Object storage secret key**: your S3 provider should give you that information.

If your project accepts untrusted pull requests, it is strongly recommended
to separate caches:

- **Untrusted CI cache**: builds triggered by pull requests or forks
- **Trusted CD cache**: builds triggered after merge or approval

This prevents unreviewed code from polluting trusted binary caches.

### Setting secrets in the CI system

Most CI systems support masked secrets, prefer using that mechanism to
a mechanism that can accidentally show the actual credentials.

The signing key is typically referenced in `nix.conf`:

```conf
secret-key-files = /path/to/signing-key
```

## Step 5: Enable cache uploads

To ensure build results are uploaded:

* The cache must be listed as a substituter
* The signing key must be available
* The CI job must have write access to the object store
* Some part of your workflow must upload the paths you care about

For the last item, there's many solutions:

- Use a `post-build-hook` to upload built paths immediately. This ensures that
  **all** store paths touched by the workflow are uploaded, including paths
  copied from <https://cache.nixos.org>.
- use a manual upload step using `nix copy $built_path s3://your-bucket?endpoint=...` at the end
- run a daemon at the same time and watch for filesystem events and copy store path as you build them

## Step 6: Run the build

Once everything is configured, run your build as usual:

```sh
nix-build -A tests
```

## Security considerations

* Never commit private signing keys
* Scope object storage credentials to the minimum required permissions (read and write here)
* Use separate caches for trusted vs untrusted builds if necessary
* Restrict who can upload to the cache
* Removing direct access to the signing key and S3 credentials is possible by
  introducing an intermediate service between CI and the cache, such as
  [Attic](https://github.com/zhaofengli/attic).
