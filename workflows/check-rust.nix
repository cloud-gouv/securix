# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ runs-on, commonSteps, ... }: {
  name = "[Sécurix] Rust workspace";

  on = {
    pull_request = { };
    push = {
      branches = [ "main" ];
    };
  };

  jobs = {
    rust = {
      inherit runs-on;
      steps = [
        commonSteps.checkout
        commonSteps.install-nix
        {
          name = "Check the Rust formatting";
          run = "nix-shell --run 'cd rust && cargo fmt --all --check'";
        }
        {
          name = "Lint the Rust workspace";
          run = "nix-shell --run 'cd rust && cargo clippy --workspace --all-targets --locked -- -D warnings'";
        }
        {
          name = "Test the Rust workspace";
          run = "nix-shell --run 'cd rust && cargo test --workspace --locked'";
        }
        {
          # The workspace must build from a checkout that holds `rust/` only.
          # This keeps the sparse-checkout rule true.
          name = "Build from a rust-only sparse checkout";
          run = ''
            # Clone the commit under test from the local checkout. Thus, the
            # job does not need to fetch a merge commit.
            git clone --no-checkout "file://$GITHUB_WORKSPACE" /tmp/rust-only
            cd /tmp/rust-only
            git sparse-checkout init --cone
            git sparse-checkout set rust
            git checkout "$(git -C "$GITHUB_WORKSPACE" rev-parse HEAD)"
            cd "$GITHUB_WORKSPACE"
            nix-shell --run 'cd /tmp/rust-only/rust && cargo build --workspace --locked'
          '';
        }
      ];
    };
  };
}
