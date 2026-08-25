# Halo Live — real data only

`VITE_API_BASE` **required**. No offline mock plate. No localStorage orders/messages.

| UI | API |
|----|-----|
| Plate / crew / photos | `GET /api/properties/:id/building-ops` + `X-Halo-Role` |
| Live stream | `GET /api/properties/:id/building-ops/stream` (SSE) |
| Jobs / board | `GET /api/jobs?propertyId=` · `PATCH /api/jobs/:id` |
| Place order | `POST /api/jobs/quick` · `POST /api/jobs/:id/client-po` |
| Chat / notes | `GET/POST /api/activities` |
| Field photos | `GET/POST /api/checkin/:token…` · storage presign |
| Work verify | `GET /api/work-verification/:jobId` (vendor) |

Role preference is the only localStorage key (`halo-live-role`).
Cart draft uses sessionStorage until checkout posts a real job.

## Board status (PATCH /api/jobs/:id)
| Column | Halo `status` |
|--------|----------------|
| Open | `scheduled` |
| In progress | `active` |
| Review | `active` |
| Complete | `complete` (requires client PO or 409) |
| Hold | `hold` |

## Pulse verify
1. `GET /api/work-reviews/job/:jobId/field-card` (opens review)
2. `POST /api/work-reviews/:id/field-submit` `{ edits: { confirmAccurate, pulseVerdict } }`
3. Approve: dismiss open discrepancies via `POST /api/work-verification/:jobId/apply-suggestion`
4. Rework: `PATCH /api/jobs/:id` `{ status: "hold" }`
