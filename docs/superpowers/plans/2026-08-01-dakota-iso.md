# Dakota ISO One-Command Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one `just build-dakota-iso` command that builds the Dakota container and creates an installer ISO targeting the Dakota stream.

**Architecture:** Reuse the existing generic container and bootc-image-builder recipes. Add thin Dakota entry points plus a checked-in Dakota installer configuration so the stream target is explicit and Stable behavior is unchanged.

**Tech Stack:** Just, Bash, Podman, bootc-image-builder, TOML, shell contract tests.

## Global Constraints

- Run on the Bluefin host using the repository's container-native tooling.
- Produce `localhost/dudley-os:dakota` and `output/bootiso/install.iso`.
- Target `ghcr.io/joshyorko/dudley-os:dakota` after installation.
- Preserve the existing Stable `build-iso` behavior.
- Do not commit or push without separate user confirmation.

---

### Task 1: Lock the Dakota ISO contract

**Files:**
- Modify: `tests/test-dakota-variant-contract.sh`

**Interfaces:**
- Consumes: repository files and `just --show` recipe output.
- Produces: a failing behavioral contract for `build-dakota`, `build-dakota-iso`, and `iso/dakota.toml`.

- [ ] **Step 1: Write the failing assertions**

Require the Dakota config to parse as TOML and target `ghcr.io/joshyorko/dudley-os:dakota`. Inspect the real expanded recipes with `just --show` and require the end-to-end recipe to invoke `build-dakota` before `_build-bib` with `localhost/dudley-os`, `dakota`, `iso`, and `iso/dakota.toml`.

- [ ] **Step 2: Verify RED**

Run: `bash tests/test-dakota-variant-contract.sh`

Expected: FAIL because `iso/dakota.toml` and the Dakota recipes do not exist.

### Task 2: Implement the one-command build

**Files:**
- Create: `iso/dakota.toml`
- Modify: `Justfile`

**Interfaces:**
- Consumes: `Containerfile.dakota`, `_build-bib`, and the repository's `image_name`/`just` variables.
- Produces: `just build-dakota` and `just build-dakota-iso`.

- [ ] **Step 1: Add the Dakota installer config**

Copy the Stable installer module configuration and change only the post-install bootc target to `ghcr.io/joshyorko/dudley-os:dakota`.

- [ ] **Step 2: Add minimal recipes**

Add `build-dakota` to invoke the existing `build` recipe with `CONTAINERFILE=./Containerfile.dakota`, target `dudley-os`, and tag `dakota`. Add `build-dakota-iso` to invoke `build-dakota`, clear the mismatched `SSH_ASKPASS` environment variable, and then invoke `_build-bib localhost/dudley-os dakota iso iso/dakota.toml`.

- [ ] **Step 3: Verify GREEN**

Run: `bash tests/test-dakota-variant-contract.sh`

Expected: PASS with `PASS: Dakota variant assembly and publish contract is present`.

### Task 3: Document and validate the operator path

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the new `build-dakota-iso` command.
- Produces: operator instructions that retain Dakota's experimental warning.

- [ ] **Step 1: Document the command**

Add a local Dakota installer example using `just build-dakota-iso` and identify `output/bootiso/install.iso` as the result.

- [ ] **Step 2: Run focused static validation**

Run: `just --list`, `just --unstable --fmt --check -f Justfile`, `python3 -c "import tomllib; tomllib.load(open('iso/dakota.toml', 'rb'))"`, `shellcheck tests/test-dakota-variant-contract.sh`, and `git diff --check`.

Expected: every command exits zero.

- [ ] **Step 3: Run repository tests**

Run: `just test-unit`.

Expected: all contract and card tests pass.

- [ ] **Step 4: Inspect the final diff**

Run: `git status --short` and `git diff --stat`.

Expected: only the design, plan, Dakota contract test, `Justfile`, `iso/dakota.toml`, and README are changed.
