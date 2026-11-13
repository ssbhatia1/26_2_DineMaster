# DineMaster — M6: Reservation Management
**Module type:** CORE, EDGE  
**Primary users:** Manager, Cashier, Waiter  
**Status:** Implementation specification derived from the DineMaster Technical Documentation. The 15-minute no-show hold is explicitly an **[ASSUMPTION]** in the source. Items marked **[PROPOSED DETAIL]** require confirmation.

---

## 1. Module objective

Support pre-booking of restaurant tables with time-slot clash detection. Staff can create, confirm, seat, cancel, and mark reservations as no-show using a 24-hour time grid.

Reservations interact with Table/Floor Management:
- A reservation may reserve a table shortly before its start time.
- Seating a reservation creates a draft order for that table.
- The same table must not have overlapping active reservations.

## 2. Scope and submodules

### 2.1 Reservation calendar / time grid
- Display reservations in a 24-hour time grid.
- Filter by date, table and status.
- Show table/time conflicts before save.

### 2.2 Create reservation
- Staff selects table and time slot.
- Enter guest name, phone and party size.
- Optional customer link and notes.
- Confirm reservation.

### 2.3 Reservation lifecycle
Supported actions in the source:
- Create
- Confirm
- Seat
- Cancel
- No-show

**[PROPOSED DETAIL]** Use a controlled state machine and reject invalid lifecycle changes instead of directly editing status from arbitrary endpoints.

### 2.4 Clash detection
- No overlapping reservation for the same table.
- Adjacent slots are allowed.
- Cancelled slots can be reused.
- Past-date handling and timezone boundaries must be tested.

### 2.5 Seating and order handoff
- On arrival, marking a reservation as Seated creates a draft order for that table.
- Table status becomes `RESERVED` shortly before reservation start, per source.
- Seating should hand off to the Order module and Table module transactionally or through a reliable idempotent workflow.

### 2.6 No-show handling
- Source assumption: default hold time is 15 minutes before marking no-show.
- This is not a confirmed business rule; make it configurable only after owner approval.
- Do not automatically mark no-show without an agreed scheduler/timezone policy.

### 2.7 Notifications
- Reminder notifications are future/later; the source says the Notification module may send reminders later.
- Do not make notification delivery a dependency for reservation creation or seating.

---

## 3. Screens and events

| Screen | Responsibility |
|---|---|
| Reservation time grid | 24-hour view of booked table slots |
| Reservation form | Guest, table, date/time, party size and notes |
| Reservation detail | Reservation state and actions: confirm, seat, cancel, no-show |

Source events:
- `ReservationsLoaded`
- `ReservationCreated`
- `ReservationSeated`

The source requires clash feedback inline before save.

**[PROPOSED DETAIL] Client states:** `ReservationsLoading`, `ReservationsLoaded`, `ReservationSaving`, `ReservationConflict`, `ReservationActionInProgress`, `ReservationError`.

---

## 4. Core workflows

### 4.1 Create and confirm a reservation
1. Staff opens reservation grid for a branch and date.
2. Selects a table and a start/end time.
3. Enters guest name, phone and party size.
4. Backend validates the table belongs to the selected branch.
5. Backend checks for overlapping active reservations.
6. If a clash exists, return conflict details and show inline feedback.
7. If no clash exists, persist reservation.
8. Reservation is confirmed according to the chosen create/confirm flow.

**[PROPOSED DETAIL]** Decide whether create defaults to `PENDING` or `CONFIRMED`; the source lists both lifecycle actions but does not state the default.

### 4.2 Guest arrives and is seated
1. Staff opens the reservation.
2. Selects `Seat`.
3. Backend verifies reservation is eligible to be seated and table is still valid.
4. Create or link a draft order for the reserved table.
5. Change reservation status to `SEATED`.
6. Update table state through Table module rules.
7. Broadcast/sync the change to connected Edge clients.

Use an idempotency key or unique relation so retrying the seat request cannot create duplicate draft orders.

### 4.3 Cancel a reservation
1. Staff opens reservation and selects Cancel.
2. Backend validates the reservation is cancellable.
3. Save `CANCELLED` status and actor/time.
4. Release its slot so another reservation can use it.
5. Broadcast the updated reservation/table availability.

### 4.4 Mark no-show
1. Staff or approved scheduled process identifies a reservation past its hold window.
2. Validate it has not been seated or cancelled.
3. Mark `NO_SHOW` and record actor or system reason.
4. Release the table reservation.
5. Do not automatically create an order.

The 15-minute hold window is an assumption and must be approved before enabling automated no-show processing.

### 4.5 Edit a reservation
1. Staff updates permitted reservation fields.
2. Re-run clash detection using the new table/time range.
3. Exclude the current reservation from its own clash query.
4. Save only if the new slot is conflict-free.

---

## 5. API specification

The source lists these endpoints:
- `GET/POST /api/v1/reservations`
- `PUT /api/v1/reservations/{id}`
- `POST /api/v1/reservations/{id}/seat`
- `POST /api/v1/reservations/{id}/cancel`

Filters: `date`, `tableId`, `status`.

### 5.1 List reservations
`GET /api/v1/reservations?date=&tableId=&status=`

**[PROPOSED DETAIL]** Require branch context, and use branch-local date/time boundaries. Return only reservations in the caller's tenant and branch.

### 5.2 Create reservation
`POST /api/v1/reservations`

**[PROPOSED DETAIL] Request**
```json
{
  "branchId": "uuid",
  "tableId": "uuid",
  "guestName": "Aarav Sharma",
  "phone": "9XXXXXXXXX",
  "partySize": 4,
  "startsAt": "2026-11-20T19:00:00+05:30",
  "endsAt": "2026-11-20T20:30:00+05:30",
  "notes": "Window-side seating"
}
```

Validation:
- Required table, guest name, phone and time range.
- `endsAt` must be after `startsAt`.
- Party size must be positive.
- Party size exceeding table seats is a warning in the source, not an automatic rejection.
- Check overlap before insert and enforce it at database level where supported.

### 5.3 Update reservation
`PUT /api/v1/reservations/{id}`

**[PROPOSED DETAIL]** Allow only approved editable fields and lifecycle transitions. Recheck clashes if table or time changes.

### 5.4 Seat reservation
`POST /api/v1/reservations/{id}/seat`

**[PROPOSED DETAIL]** Request may include `idempotencyKey`; response should include reservation, table and created draft-order identifiers.

### 5.5 Cancel reservation
`POST /api/v1/reservations/{id}/cancel`

**[PROPOSED DETAIL]** Capture cancellation reason when required by business policy.

### 5.6 No-show endpoint
The source lists no dedicated route for no-show. **[PROPOSED DETAIL]** If manual no-show is required, add `POST /api/v1/reservations/{id}/no-show` after API review; otherwise process it through an approved scheduled job.

---

## 6. Database design

The source specifies:

`core.reservations(id, tenant_id, branch_id, table_id, customer_id, guest_name, phone, party_size, starts_at, ends_at, status, notes, ...)`

### 6.1 Field responsibilities

| Field | Purpose |
|---|---|
| `id` | Reservation UUID |
| `tenant_id` | Tenant isolation |
| `branch_id` | Branch ownership |
| `table_id` | Reserved table |
| `customer_id` | Optional customer reference |
| `guest_name` | Guest name |
| `phone` | Contact number; protect as personal data |
| `party_size` | Number of guests |
| `starts_at`, `ends_at` | Reservation interval |
| `status` | Lifecycle state |
| `notes` | Optional staff notes |
| `created_at`, `updated_at` | **[PROPOSED DETAIL]** timestamps |
| `created_by` | **[PROPOSED DETAIL]** audit actor |

### 6.2 Prevent overlapping reservations

The source proposes a PostgreSQL exclusion constraint:

```sql
EXCLUDE USING gist (
  table_id WITH =,
  tstzrange(starts_at, ends_at) WITH &&
)
WHERE status IN ('PENDING', 'CONFIRMED', 'SEATED');
```

This prevents overlapping active intervals for the same table. Ensure required PostgreSQL operator classes/extensions (commonly `btree_gist` for UUID equality) are installed as part of migration if needed.

For SQLite Edge, the source specifies checking in code inside a transaction. A plain check outside a transaction is unsafe under concurrent requests.

### 6.3 Clash query

The source defines the overlap predicate:

```sql
SELECT EXISTS (
  SELECT 1
  FROM core.reservations r
  WHERE r.table_id = :table_id
    AND r.status IN ('PENDING', 'CONFIRMED', 'SEATED')
    AND r.starts_at < :new_end
    AND r.ends_at > :new_start
    AND (:current_id IS NULL OR r.id <> :current_id)
);
```

Use half-open interval semantics: `existing.start < new.end AND existing.end > new.start`. This permits adjacent slots where one reservation ends exactly when the next begins.

---

## 7. Business rules and validation

| Rule | Expected behaviour |
|---|---|
| Same table overlap | Not allowed for active reservation statuses |
| Adjacent time slots | Allowed |
| Cancelled reservation | Does not block slot reuse |
| Party size vs seats | Warning only, as specified in source |
| Reservation time | Use branch timezone for grid and date filters |
| Past date | Must be tested; exact policy requires confirmation |
| Table reservation | Table becomes `RESERVED` shortly before start |
| Seat action | Creates a draft order for that table |
| Phone number | Protected; do not expose unnecessarily |
| Creator | Record who created reservation |
| No-show grace period | 15 minutes is an unconfirmed assumption |

### Suggested lifecycle model [PROPOSED DETAIL]
- `PENDING`
- `CONFIRMED`
- `SEATED`
- `CANCELLED`
- `NO_SHOW`

Possible transitions:
- `PENDING → CONFIRMED`
- `PENDING → CANCELLED`
- `CONFIRMED → SEATED`
- `CONFIRMED → CANCELLED`
- `CONFIRMED → NO_SHOW`
- `PENDING → NO_SHOW` only if product policy permits it

Do not implement this matrix until it is approved; the source names the states/actions but does not provide the complete transition table.

---

## 8. Architecture and integrations

### Backend
- `ReservationController`
- `ReservationService`
- `ReservationService.checkClash`
- Reservation repository
- Table/Floor integration
- Order integration for draft-order creation
- Optional notification integration in a later phase

### Edge
- Reservation list/grid should remain usable from local branch data when offline, subject to the project sync rules.
- SQLite clash check must execute within a transaction.
- Edge controls live table reservation state at the branch.
- Sync reservation changes without duplicating records.

### Cloud
- Persist and synchronise reservation data.
- Enforce tenant/branch ownership.
- Preserve branch timezone semantics.
- Avoid conflicting writes with Edge-originated changes.

### Dependencies
- M5 Table and Floor Management
- M11 Order Management (draft order creation)
- M2 User and Staff Management (creator/actor identity)
- M1 Authentication and Authorization (permissions)
- Notification module only for future reminders

---

## 9. Security, privacy and audit

- Enforce tenant and branch scoping for every read/write.
- Only authorised Manager, Cashier or Waiter users can use reservation actions according to configured permissions.
- Protect guest phone number; avoid exposing it in broad floor-plan responses.
- Log reservation creator and lifecycle changes.
- **[PROPOSED DETAIL]** Audit old/new status, actor, timestamp, branch, device and request ID.
- Apply the organisation's retention and privacy policy to guest contact details.
- Do not include guest phone numbers in WebSocket events unless the receiving client needs them.

---

## 10. Error handling

| HTTP | Use |
|---|---|
| `400` | Malformed request |
| `401` | Missing/invalid authentication |
| `403` | User lacks reservation permission |
| `404` | Reservation/table not found within caller's scope |
| `409` | Time clash, invalid lifecycle transition, table/order conflict |
| `422` | Invalid time range or party size, if used by project convention |

For a clash, return a stable error code such as `RESERVATION_TIME_CONFLICT` and enough safe information for inline UI feedback.

---

## 11. Testing checklist

### Unit tests
- Clash predicate with overlap.
- Adjacent slots allowed.
- Cancelled reservation does not block a slot.
- Current reservation excluded during edit.
- Timezone conversion and branch-local date filtering.
- Lifecycle transition validation.

### Integration tests
- Create and list reservations.
- Update reservation time and table.
- Seat reservation creates exactly one draft order.
- Cancel reservation releases the slot.
- No-show releases the slot.
- Table becomes Reserved according to the configured pre-start policy.

### Database/concurrency tests
- PostgreSQL exclusion constraint rejects overlapping inserts.
- SQLite transaction-level check prevents conflicting local writes.
- Two concurrent requests for the same table/time cannot both succeed.
- Repeated seat request does not create duplicate orders.

### Privacy/security tests
- Cross-tenant reservation lookup denied.
- Cross-branch access denied.
- Phone number masked/omitted where caller does not need it.
- Creator and lifecycle actor are recorded.

### Acceptance criteria
- Staff can create, confirm, seat, cancel and mark no-show.
- Same-table overlapping active reservations are rejected.
- Adjacent slots are allowed.
- Clash is shown inline before save.
- Seating creates a draft order for the reserved table.
- Branch timezone boundaries are correct.
- Guest phone data is protected.

---

## 12. Recommended implementation sequence

1. Confirm reservation statuses and lifecycle transitions.
2. Confirm branch timezone source and past-date policy.
3. Create `core.reservations` migration.
4. Add PostgreSQL exclusion constraint and SQLite transactional clash guard.
5. Implement `ReservationService.checkClash`.
6. Implement create/list/update APIs and filters.
7. Implement confirm/cancel/no-show actions.
8. Integrate seat action with Table and Order modules using idempotency.
9. Implement pre-start table `RESERVED` behaviour.
10. Build Flutter time grid, form and detail screens.
11. Add offline sync, privacy and concurrency tests.
12. Add reminders only when Notification module is ready.

---

## 13. Open decisions before production

- Is a new reservation `PENDING` or `CONFIRMED` by default?
- What are the exact allowed lifecycle transitions?
- Is the 15-minute no-show grace period approved? Is it configurable per branch?
- How early should a table become `RESERVED` before start time?
- What is the default reservation duration if staff selects only a start time?
- What is the policy for past-time and walk-in reservations?
- Can one reservation cover multiple tables?
- What should happen if the table is unavailable when the guest arrives?
- Which roles may mark no-show?
- What guest-data retention and masking policy applies?

---

**Source boundary:** The source document specifies reservation purpose, users, actions, 24-hour grid, no-overlap rule, 15-minute no-show assumption, seating workflow, screens/events, service, table definition, PostgreSQL exclusion constraint, SQLite transactional check, endpoints, filters, dependencies and tests. Payload shapes, additional lifecycle details, no-show endpoint, idempotency and audit fields marked **[PROPOSED DETAIL]** are engineering recommendations, not confirmed source requirements.
