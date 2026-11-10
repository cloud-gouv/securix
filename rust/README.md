<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>

SPDX-License-Identifier: MIT
-->

# Sécurix Rust workspace

This workspace holds the Rust code of Sécurix. All Rust code of the project
lives here.

The code covers the components that run on a Sécurix machine:

- system daemons,
- agents that run in a user session,
- command-line tools,
- the libraries that the three share.

## What belongs here

Put code here if it runs on the machine and it needs safety beyond what a Bash
script can afford.

Do not put these files here:

- Nix modules and packages. They stay in `modules/` and `pkgs/`.
- Documentation. It stays in `docs/`.
- Shell scripts that need no library.

## Layout

```
rust/
  Cargo.toml
  Cargo.lock
  rust-toolchain.toml
  crates/
    ...                    # any crate required (library, binaries, etc.)
```

## Add a crate

1. Make the directory `crates/<name>/`.
2. Write its `Cargo.toml`. Use `edition.workspace = true` and the other
   `workspace` keys.
3. Add `[lints] workspace = true`.
4. Run `cargo build --workspace --locked`. Cargo adds the crate to the
   workspace because the members are `crates/*`.
5. Commit the new `Cargo.lock`.

## Build and test

Run these commands:

```bash
cd rust
cargo build --workspace --locked
cargo test --workspace --locked
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
```

nixpkgs gives the toolchain for the Nix build.

We use a Nix dev shell for the repository.

## Rules

- Each crate uses the workspace lints. The build denies `unsafe_code`.
- Clippy uses the `pedantic` and `nursery` groups. Fix the cause of a warning.
  Do not silence it.
- A test must show a behaviour. Do not write a test that repeats a constant.
- Each file has an SPDX header.
- Put a new dependency in `[workspace.dependencies]`. A crate then uses
  `workspace = true`. This keeps one version of each dependency.

## Sparse-checkout rule

No file under `rust/` refers to a path outside `rust/`. This is done to enable
users to depend on this code without checking out the rest of the Sécurix
monorepository.

As a result, these commands work:

```bash
git clone --filter=blob:none --no-checkout https://github.com/cloud-gouv/securix
cd securix && git sparse-checkout init --cone
git sparse-checkout set rust
git checkout main && cd rust && cargo build --workspace --locked
```

The CI enforces this by building the workspace alone.

## Licenses

Each file uses the MIT license.
