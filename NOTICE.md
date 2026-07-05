# Third-Party License Notice

Stock Plan Manager is distributed under the [MIT License](LICENSE). This
`NOTICE.md` records the licenses of the third-party dependencies it uses, as
required for an open-source release.

The inventory below covers every dependency resolved in `mix.lock` (direct and
transitive). Each was audited against the project's permissive allowlist
(**MIT / Apache-2.0 / BSD / ISC**).

> **How this audit was produced.** The plan called for `licensir` (`mix
> licenses`). `licensir` 0.7.0 is archived upstream (last released 2021) and is
> incompatible with this project's toolchain (Elixir 1.19 / Mix 1.19 / OTP 28) —
> `mix licenses` fails with `UndefinedFunctionError: Mix.Dep.loaded/1`. Per the
> phase research's documented fallback, licenses were read directly from each
> dependency's `deps/<pkg>/hex_metadata.config` (the same source `licensir`
> itself consults). `heroicons` is a sparse git checkout with no
> `hex_metadata.config`; its license was confirmed as MIT via the GitHub license
> API. `licensir` remains declared in `mix.exs` as a dev-only tool
> (`only: :dev, runtime: false`) and is never shipped in a release.

## Dependency License Inventory

All dependencies are permissive (MIT / Apache-2.0) **except `erlsom`**, which is
LGPL-3.0 — see the dedicated section below.

| Package | Version | License | Allowlist |
|---|---|---|---|
| bandit | 1.10.4 | MIT | ✓ permissive |
| cc_precompiler | 0.1.11 | Apache-2.0 | ✓ permissive |
| db_connection | 2.10.0 | Apache-2.0 | ✓ permissive |
| decimal | 2.3.0 | Apache-2.0 | ✓ permissive |
| dns_cluster | 0.2.0 | MIT | ✓ permissive |
| ecto | 3.13.5 | Apache-2.0 | ✓ permissive |
| ecto_sql | 3.13.5 | Apache-2.0 | ✓ permissive |
| ecto_sqlite3 | 0.22.0 | MIT | ✓ permissive |
| elixir_make | 0.9.0 | Apache-2.0 | ✓ permissive |
| **erlsom** | **1.5.2** | **LGPL-3.0** (declared "GNU Lesser GPL, Version 3") | ⚠ copyleft — see below |
| esbuild | 0.10.0 | MIT | ✓ permissive |
| expo | 1.1.1 | Apache-2.0 | ✓ permissive |
| exqlite | 0.36.0 | MIT | ✓ permissive |
| file_system | 1.1.1 | Apache-2.0 | ✓ permissive |
| finch | 0.21.0 | MIT | ✓ permissive |
| fine | 0.1.6 | Apache-2.0 | ✓ permissive |
| gettext | 1.0.2 | Apache-2.0 | ✓ permissive |
| heroicons | v2.2.0 | MIT (verified via GitHub license API) | ✓ permissive |
| hpax | 1.0.3 | Apache-2.0 | ✓ permissive |
| jason | 1.4.4 | Apache-2.0 | ✓ permissive |
| lazy_html | 0.1.11 | Apache-2.0 | ✓ permissive |
| licensir | 0.7.0 | MIT | ✓ permissive (dev-only) |
| mime | 2.0.7 | Apache-2.0 | ✓ permissive |
| mint | 1.7.1 | Apache-2.0 | ✓ permissive |
| nimble_options | 1.1.1 | Apache-2.0 | ✓ permissive |
| nimble_pool | 1.1.0 | Apache-2.0 | ✓ permissive |
| phoenix | 1.8.5 | MIT | ✓ permissive |
| phoenix_ecto | 4.7.0 | MIT | ✓ permissive |
| phoenix_html | 4.3.0 | MIT | ✓ permissive |
| phoenix_live_reload | 1.6.2 | MIT | ✓ permissive |
| phoenix_live_view | 1.1.28 | MIT | ✓ permissive |
| phoenix_pubsub | 2.2.0 | MIT | ✓ permissive |
| phoenix_template | 1.0.4 | MIT | ✓ permissive |
| plug | 1.19.1 | Apache-2.0 | ✓ permissive |
| plug_crypto | 2.1.1 | Apache-2.0 | ✓ permissive |
| req | 0.5.17 | Apache-2.0 | ✓ permissive |
| tailwind | 0.4.1 | MIT | ✓ permissive |
| telemetry | 1.4.1 | Apache-2.0 | ✓ permissive |
| telemetry_metrics | 1.1.0 | Apache-2.0 | ✓ permissive |
| telemetry_poller | 1.3.0 | Apache-2.0 | ✓ permissive |
| thousand_island | 1.4.3 | MIT | ✓ permissive |
| websock | 0.5.3 | MIT | ✓ permissive |
| websock_adapter | 0.5.9 | MIT | ✓ permissive |
| xlsxir | 1.6.4 | MIT | ✓ permissive |

## erlsom — LGPL-3.0 (copyleft) disposition

**Finding.** `erlsom` 1.5.2 is licensed under the **GNU Lesser General Public
License, Version 3 (LGPL-3.0)**. It is not on the project's permissive allowlist.
It enters the dependency graph transitively — it is a runtime dependency of
`xlsxir` (`{:erlsom, "~> 1.5"}`), the library that parses E*Trade Benefit History
XLSX files. It is not declared directly in this project's `mix.exs`.

**Disposition: DOCUMENT (keep the dependency; record it here).** After the audit
surfaced this copyleft finding, it was raised for an explicit human decision (the
project's acceptance bar treats any copyleft finding as a blocker to raise, not
to silently ship). The decision is to **retain `xlsxir`/`erlsom` and document the
LGPL obligation here**, rather than replace the XLSX parser.

**Why this satisfies LGPL-3.0's obligations:**

- **Unmodified library.** `erlsom` is used exactly as published on Hex — it is a
  clean, unmodified package. Stock Plan Manager makes no changes to `erlsom`'s
  source.
- **Not redistributed in this repository.** `/deps/` is gitignored; `erlsom`'s
  source is not vendored or redistributed as part of this repo. Each user fetches
  `erlsom` themselves from Hex via `mix deps.get` when they build the app.
- **Source remains available.** `erlsom` ships its complete source under LGPL-3.0
  on Hex and upstream at <https://github.com/willemdj/erlsom>. Its own license
  terms and source stay intact and available to any user.
- **Use as a library / dynamic linking.** The application links `erlsom` as a
  library. On the BEAM, modules are loaded dynamically at runtime, and the app
  consumes `erlsom` only through its public API (via `xlsxir`) — it does not
  create a derivative work of `erlsom` itself.
- **Relink / replace freedom.** A user may substitute a different (including
  modified) version of `erlsom` by editing `mix.lock` / `mix.exs` and rebuilding
  from source with `mix deps.get` + `mix compile`. This preserves the LGPL
  relinking freedom — users are free to run the app against their own build of
  `erlsom`.

This is the standard, broadly-accepted pattern for an LGPL-licensed library used
by an MIT-licensed application. The rest of the application remains under the MIT
License; only `erlsom` itself is subject to LGPL-3.0, and its terms are
preserved.

> **Not legal advice.** This notice reflects a good-faith open-source licensing
> assessment, not legal counsel. If formal sign-off is required, confirm the
> `erlsom`/LGPL-3.0 disposition with a qualified attorney.

---

*License data sourced from each package's `hex_metadata.config` (Hex-declared
licenses) as resolved in `mix.lock`. To regenerate the inventory after a
dependency change, re-run the audit against `deps/*/hex_metadata.config`.*
