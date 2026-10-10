# HALO dependency supply-chain baseline

Baseline branch: `codex/halo-enterprise-reconciliation-rc1`

## Reproducible installation

- The web application and isolated workflow service each have an npm lockfile (lockfile version 3).
- CI installs both dependency trees with `npm ci` on Node.js 22.
- The web workflow builds and lints the checked-out SHA after a clean locked install.
- The PostgreSQL workflow runs its domain and database suites after a clean locked install.

## Vulnerability scan

`npm audit --audit-level=moderate` reported zero known vulnerabilities in both locked dependency trees when this baseline was created. CI repeats the same gate. Registry results can change, so every release SHA must rerun it.

## License inventory

The lockfiles record the following declared license identifiers:

| License | Web packages | Workflow-service packages |
|---|---:|---:|
| MIT | 234 | 12 |
| ISC | 18 | 2 |
| MPL-2.0 | 12 | 0 |
| BlueOak-1.0.0 | 10 | 0 |
| Apache-2.0 | 4 | 0 |
| Hippocratic-2.1 | 2 | 0 |
| 0BSD | 2 | 0 |
| Unlicense | 1 | 0 |
| CC-BY-4.0 | 1 | 0 |
| BSD-3-Clause | 1 | 0 |
| BSD-2-Clause | 1 | 0 |

The two Hippocratic-2.1 entries are the direct production dependencies `react-leaflet` and `@react-leaflet/core`. This is a non-standard ethical-use license and requires explicit product/legal acceptance before commercial production release. The MPL-2.0 and CC-BY-4.0 packages are build-time dependencies; preserve their notices and comply with their license terms in distributed source and attribution materials.

`npm run audit:licenses` fails CI if either lockfile contains a dependency without a declared license or a license identifier outside this reviewed baseline. Adding a new license therefore requires an explicit code review update rather than silently expanding the accepted set.

## Release rule

Do not hand-edit lockfiles. Dependency changes must update the relevant manifest and lockfile together, pass the web and PostgreSQL workflows, rerun the vulnerability scan, and review new or changed licenses.
