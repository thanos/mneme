# Versioning Policy

This project tracks three independent version surfaces:

- library/package semantic version (`vX.Y.Z`)
- C ABI version (`mneme_abi_version()`)
- file format version (`format_version` in `.mneme`)

## 1) Library SemVer

`mneme` follows SemVer-style release tags for project milestones.

- patch (`Z`): bug fixes and documentation updates
- minor (`Y`): backward-compatible feature additions
- major (`X`): breaking changes to public API/ABI/behavior contracts

Current target release line for this phase: `v0.5.0`.

## 2) C ABI Versioning

C ABI version is reported at runtime via:

- `uint32_t mneme_abi_version(void);`

Current ABI version: `1`.

Rules:

- breaking ABI changes must bump ABI version
- additive changes may keep ABI version
- wrappers should probe symbols for additive features on the same ABI version

## 3) File Format Versioning

`.mneme` files carry an explicit `format_version`.

Current format version: `2`.

Rules:

- any incompatible format change must bump `format_version`
- readers should keep support for older stable versions when practical
- unknown future versions must fail safely

## Example Version Tuple

For current Phase 5 productization milestone:

- Library: `v0.5.0`
- ABI: `v1`
- Format: `v2`

## Release Workflow

Tags starting with `v` are used for GitHub release publishing and binary asset naming.
The release workflow publishes per-platform C ABI archives that wrappers can consume.
