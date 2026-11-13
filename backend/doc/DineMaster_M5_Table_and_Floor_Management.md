# DineMaster — M5: Table and Floor Management
**Module type:** CORE, EDGE  
**Primary users:** Manager, Cashier, Waiter  
**Status:** Implementation specification derived from the DineMaster Technical Documentation. Items explicitly marked **[PROPOSED DETAIL]** expand the source for implementation and should be confirmed before production.

---

## 1. Module objective

Provide a digital floor plan with live table status so staff can seat guests quickly, avoid double seating, assign waiters, and coordinate table cleaning.

The Edge database is the authority for live table status at a branch. The Cloud stores/synchronises the relevant data according to the wider offline-sync architecture.

## 2. Scope and submodules

### 2.1 Floor and zone management
- Create and maintain floors/zones such as Main Hall, AC Room, Terrace, Bar, Private Dining, and Banquet.
- List floors for the active branch.
- Keep floor/table ownership within the current tenant and branch.
- **[PROPOSED DETAIL]** Support floor name, display order, active flag, and optional description.

### 2.2 Table layout management
- Create and edit tables with label, seat capacity, and visual position.
- Render tables in a floor-plan grid.
- Layout edits are blocked while a table has an open order.
- **[PROPOSED DETAIL]** Store coordinates or grid row/column and optional shape/rotation only if the UI requires them.

### 2.3 Live table status
- Display colour-coded live status.
- Change status only through the approved state-transition rules in the master document's Table Status section (7.4).
- Illegal transitions return HTTP `409 Conflict`.
- Edge remains the live status authority.

### 2.4 Waiter assignment
- Assign a waiter to a table.
- A waiter may change status only for tables assigned to that waiter.
- Manager/Cashier access follows the role and permission configuration.

### 2.5 Seating workflow
- Waiter taps an available table.
- Sets guest count and assigns self.
- Starts an order for the table.
- One table can have only one open order, except for the documented split-bill case.

### 2.6 Cleaning workflow
- After payment, table moves to `Cleaning`.
- Staff marks it `Available` after cleaning.
- Do not mark a table available merely because payment completed.

### 2.7 Merge and transfer
- Table merge and transfer are listed as **Target** in the source document, not as baseline MVP behaviour.
- Keep them out of the first release unless product owner explicitly approves the workflow and order reassignment rules.

---

## 3. Screens and client events

| Screen | Responsibility |
|---|---|
| Floor plan grid | Show floors, tables, capacity and live status |
| Table detail sheet | Show selected table, current status, waiter and open-order context |
| Layout editor (Admin) | Create/edit floor and table positions |

Recommended client events/states from the source:
- Events: `TablesLoaded`, `TableTapped`, `TableStatusChanged`, `WaiterAssigned`
- **[PROPOSED DETAIL]** States: `TablesLoading`, `FloorPlanLoaded`, `TableActionInProgress`, `TableActionFailed`, `FloorPlanError`

The UI should refresh from Edge/WebSocket events, including `table.status_changed`, rather than relying only on a local optimistic update.

---

## 4. Core workflows

### 4.1 Configure a floor
1. Admin opens the layout editor.
2. Selects the active branch.
3. Creates or selects a floor/zone.
4. Adds tables with unique labels within the floor (uniqueness scope **[PROPOSED DETAIL]**).
5. Sets seat capacity and visual position.
6. Saves the layout.
7. Backend validates branch ownership and checks that no affected table has an open order.
8. Edge persists the layout and broadcasts the updated floor plan.

### 4.2 Seat walk-in guests
1. Waiter opens the floor plan.
2. Selects an `AVAILABLE` table.
3. Enters guest count.
4. Assigns self as waiter.
5. System atomically claims the table and creates/links the draft order through the Order module.
6. Other devices receive the table status update.
7. If another waiter claimed the table first, the second request receives `409 Conflict`; client reloads the table state.

### 4.3 Complete service and clean table
1. Order/payment workflow completes payment.
2. Order module drives the table status to `Cleaning`.
3. Cleaning staff checks the table.
4. Staff marks it `Available`.
5. Edge broadcasts `table.status_changed`.

### 4.4 Assign or change waiter
1. Authorised user opens table details.
2. Selects an active waiter available for the branch.
3. Backend validates assignment permission and branch scope.
4. Assignment is saved and a `WaiterAssigned`/table update is broadcast.

### 4.5 Edit layout
1. Admin opens layout editor.
2. Backend checks all affected tables for open orders.
3. If any table has an open order, reject the edit with `409 Conflict`.
4. Otherwise save the layout and publish the updated layout to clients.

---

## 5. API specification

The following routes are explicitly listed in the source document. Request/response fields below are implementation guidance and should be aligned with the existing OpenAPI contract.

### 5.1 List floors
`GET /api/v1/floors`

**Purpose:** Retrieve floors for the authenticated tenant and selected branch.

**[PROPOSED DETAIL] Query parameters**
- `branchId` — required unless resolved from the authenticated device/session.
- `includeInactive` — Admin-only optional flag.

**Expected response shape [PROPOSED DETAIL]**
```json
{
  "items": [
    {
      "id": "uuid",
      "name": "Main Hall",
      "branchId": "uuid",
      "displayOrder": 1,
      "isActive": true
    }
  ]
}
```

### 5.2 List tables
`GET /api/v1/tables?floorId=&status=`

**Purpose:** Get tables, optionally filtered by floor and status.

**[PROPOSED DETAIL]** Support pagination only if floor sizes justify it; a floor plan generally benefits from returning all active tables for one floor in a single response.

### 5.3 Change table status
`PUT /api/v1/tables/{id}/status`

**[PROPOSED DETAIL] Request**
```json
{
  "status": "CLEANING",
  "version": 12
}
```
- Validate legal transition using master status matrix 7.4.
- Validate tenant, branch and role.
- Validate waiter assignment when caller is a Waiter.
- Use transaction/optimistic concurrency to prevent double seating.
- Return `409` for illegal transition or concurrent state conflict.

### 5.4 Assign waiter
`PUT /api/v1/tables/{id}/waiter`

**[PROPOSED DETAIL] Request**
```json
{
  "waiterId": "uuid"
}
```
Validate that waiter is active and assigned to the same branch.

### 5.5 Create/update layout
`POST /api/v1/tables` — create table  
`PUT /api/v1/tables` — update layout, as listed in the source

**[PROPOSED DETAIL]** If multiple tables are saved as one layout, accept a batch payload and validate the complete layout atomically. Do not silently overwrite live status fields from layout updates.

---

## 6. Database design

The source identifies:
- `core.floors`
- `core.dining_tables` (schema reference 6.5)

Exact DDL must follow the supplied database schema. The following is a conceptual field checklist, not a replacement for the canonical schema.

### 6.1 `core.floors`
| Field | Purpose |
|---|---|
| `id` | UUID primary key |
| `tenant_id` | Tenant isolation |
| `branch_id` | Owning branch |
| `name` | Floor/zone name |
| `display_order` | UI ordering |
| `is_active` | Soft enable/disable |
| `created_at`, `updated_at` | Audit timestamps |

### 6.2 `core.dining_tables`
| Field | Purpose |
|---|---|
| `id` | UUID primary key |
| `tenant_id`, `branch_id` | Isolation and ownership |
| `floor_id` | Parent floor |
| `label` | Visible table label |
| `seats` | Seating capacity |
| `position` | Layout position/metadata |
| `status` | Current table status |
| `waiter_id` | Assigned waiter, nullable |
| `version` | **[PROPOSED DETAIL]** optimistic concurrency |
| `created_at`, `updated_at` | Timestamps |

**Important constraints**
- All reads/writes must be tenant- and branch-scoped.
- Table status is owned by Edge for live operation.
- Enforce one open order per table in the Order/Edge transaction boundary, except supported split-bill behaviour.
- Do not permit layout edits while an open order exists.
- Preserve sync metadata required by the project-wide offline synchronisation design.

---

## 7. Business rules and validation

| Rule | Expected behaviour |
|---|---|
| One open order per table | Reject a second open order, except split-bill flow |
| Double seating | One concurrent request succeeds; competing request receives `409` |
| Layout edit with open order | Reject with `409` |
| Waiter table access | Waiter can change status only for assigned tables |
| Invalid status transition | Reject with `409` |
| Guest count | **[PROPOSED DETAIL]** must be a positive integer; warn if greater than table capacity |
| Table capacity | Must be positive |
| Table label | Required and unique within an agreed scope |
| Branch isolation | Cross-branch table access must be denied |

The exact allowed status values and transitions must be taken from master document section 7.4; do not invent a second status list in code.

---

## 8. Architecture and integration

### Backend components
- `TableController`
- `TableService` — status guard and transactional seating protection
- `FloorService`
- Repositories for floors and dining tables
- Order integration for open-order checks and order-driven status changes

### Edge responsibilities
- Own live table status while the branch is operating.
- Commit status changes transactionally.
- Broadcast `table.status_changed`.
- Keep the floor plan usable while Cloud is unavailable.
- Queue/synchronise changes according to the global sync design.

### Cloud responsibilities
- Store/synchronise floor and table configuration.
- Respect tenant/branch boundaries.
- Do not overwrite newer Edge live status with stale configuration sync.

### Dependencies
- Order module drives table status.
- Reservation module reserves tables.
- User/Staff module supplies waiter identities and branch assignments.
- Authentication/Authorization supplies permissions.

---

## 9. Security and audit

- Enforce tenant and branch scoping in the service/repository layer, not only in the UI.
- Verify role/permission for floor layout changes.
- Waiter may update only assigned tables.
- Record who changed table status, assigned a waiter, or edited layout.
- Do not expose another branch's floor/table identifiers through list or detail endpoints.
- **[PROPOSED DETAIL]** Audit record should include actor, table ID, old status, new status, timestamp, device ID and request/correlation ID.

---

## 10. Error handling

| HTTP | Use |
|---|---|
| `400` | Invalid request fields |
| `401` | Missing/invalid authentication |
| `403` | Authenticated user lacks permission |
| `404` | Table/floor not found within caller's scope |
| `409` | Illegal status transition, concurrent seating, open order blocks layout edit |
| `422` | Semantically invalid layout/capacity, if this convention is used project-wide |

Return stable machine-readable error codes in addition to a human-readable message.

---

## 11. Testing checklist

### Unit tests
- Floor/table validation.
- Table status transition guard against section 7.4.
- Waiter assignment validation.
- Open-order guard before layout edit.
- Tenant/branch scoping.

### Integration tests
- Create floor and tables.
- List tables by floor and status.
- Assign waiter and verify branch membership.
- Payment completion moves table to Cleaning.
- Cleaning completion makes table Available.
- Invalid transition returns `409`.

### Concurrency tests
- Two waiters attempt to seat the same table simultaneously; exactly one succeeds.
- Two devices attempt conflicting status updates.
- Layout update races with order creation; one operation must be rejected safely.

### Offline/realtime tests
- Cloud unavailable; Edge floor plan remains usable.
- Reconnect and sync without duplicate events.
- WebSocket reconnect receives current table state or replayed event.
- `table.status_changed` updates all connected clients.

### Acceptance criteria
- A branch can view its floor plan and live table statuses.
- Concurrent seating cannot create two open orders for one table.
- Waiters cannot change unassigned tables.
- Paid tables enter Cleaning; staff explicitly marks Available.
- Layout changes are blocked for tables with open orders.

---

## 12. Recommended implementation sequence

1. Confirm status matrix from section 7.4 and canonical schema 6.5.
2. Create/verify Flyway migrations for floors and dining tables.
3. Implement tenant/branch-scoped repositories.
4. Implement floor and table read APIs.
5. Implement status transition guard in `TableService`.
6. Implement atomic seating/open-order protection with Order module.
7. Implement waiter assignment and permission checks.
8. Implement layout create/update with open-order guard.
9. Implement Edge live status and WebSocket event.
10. Implement Flutter floor grid, table detail sheet and Admin layout editor.
11. Add concurrency, offline and integration tests.

## 13. Open decisions before production

- Confirm exact status enum and transition matrix from section 7.4.
- Confirm whether table labels are unique per floor or per branch.
- Confirm layout coordinate format and supported table shapes.
- Confirm split-bill representation and how it affects the one-open-order rule.
- Confirm whether merge/transfer is deferred (source says Target).
- Confirm how status changes are reconciled if Cloud and Edge reconnect after long offline periods.

---

**Source boundary:** The source document specifies the module purpose, user roles, zones, core rules, screens/events, services, tables, endpoints, dependencies and tests. Detailed payload fields, extra constraints, audit shape and implementation steps marked **[PROPOSED DETAIL]** are engineering elaborations, not confirmed source requirements.
