# HarborWing Air Database (IT8 Midterm Drill / Part 1)

> **Part 2 (CRUD application):** https://github.com/201980287manio/harborwing-crud.git
> **Explainer video:** https://drive.google.com/file/d/1_BHv9pcm4pZprOgos-nJI-LummV-aPoL/view?usp=drive_link

A relational MySQL database for **HarborWing Air**, a fictional regional airline. It replaces the airline's spreadsheets and fixes their problems: repeated passenger data, inconsistent airport names, hard-to-track connecting flights, duplicated payments, overwritten actual times, and lost cost history.

## Repository contents

```
harborwing-db/
├── README.md
├── database/
│   ├── 01_schema.sql           Tables, keys, constraints, indexes (also resets the DB)
│   ├── 02_example_queries.sql  Example queries
│   └── 03_row_counts.sql       Row count of every table
├── seed/
│   ├── seed.py                 Faker-based data generator
│   ├── requirements.txt        Python dependencies
│   ├── .env.example            Connection settings template (copy to .env)
│   └── .gitignore              Keeps .env and venv out of git
└── docs/
    ├── harborwing_eer.mwb      MySQL Workbench model
    └── harborwing_eer.png      Exported EER diagram
```

## Database diagram

![HarborWing EER diagram](docs/harborwing_eer.png)

The editable model is `docs/harborwing_eer.mwb`.

---

## Quick start (create, seed, query)

**Requirements:** MySQL 8 (or MariaDB 10.5+) and Python 3.10+. This project was built with XAMPP, where MySQL listens on port **3307**. Adjust the port if yours differs.

1. **Create an empty database**
   ```sql
   CREATE DATABASE harborwing_air CHARACTER SET utf8mb4;
   ```
   (In phpMyAdmin: click **New**, name it `harborwing_air`, and create it.)

2. **Create the tables.** Run `database/01_schema.sql` against that database. In phpMyAdmin, open the database, go to the **SQL** tab, paste the file, and click **Go** (or use **Import**). From a terminal:
   ```
   mysql -h 127.0.0.1 -P 3307 -u root harborwing_air < database/01_schema.sql
   ```
   The red markers phpMyAdmin's editor shows on `CHECK` lines are false alarms from its built-in checker; the server accepts them.

3. **Configure the seed script**
   ```
   cd seed
   copy .env.example .env        (macOS/Linux: cp .env.example .env)
   ```
   Edit `.env` if your host, port, user, password or database name differ. Never commit `.env`.

4. **Install dependencies and generate the data**
   ```
   python -m venv venv
   venv\Scripts\activate         (macOS/Linux: source venv/bin/activate)
   pip install -r requirements.txt
   python seed.py
   ```
   The script prints the rows inserted per table and a row-count check that every table has at least 50 rows.

5. **Verify and query.** Run `database/03_row_counts.sql` for the counts and `database/02_example_queries.sql` for the example queries (run them one at a time).

### Reset process
The seed script is **repeatable**: it uses a fixed random seed (`42`) and a fixed reference date (2026-10-15), and it empties every table (`TRUNCATE` with foreign key checks temporarily off) before inserting. To reset, just run `python seed.py` again. To rebuild the structure too, re-run `database/01_schema.sql`, which drops and recreates all tables, then run the seed script.

### Seeded data

| Table | Rows |
|---|---|
| booking_agent | 55 |
| passenger | 120 |
| airport | 60 |
| calendar_date | 730 (2026-01-01 to 2027-12-31) |
| flight_schedule | 80 |
| flight_leg | 120 |
| flight_cost | 163 |
| reservation | 150 |
| payment | 140 |
| reservation_payment | 291 |
| reservation_leg | 279 |

All data is fictional (Faker). Parent rows are inserted before children, foreign keys always point to existing rows, and composite pairs are generated through sets so duplicates are impossible. The data includes direct and agent-assisted reservations (about 35% direct), reservations with several payments and several legs, payments shared by several reservations, flights with several cost validity periods, and legs with unknown actual times (flights that have not operated yet).

---

## Tables and their purpose

| Table | Purpose | Key |
|---|---|---|
| `booking_agent` | Agents who make bookings on behalf of passengers | `agent_id` |
| `passenger` | Main passengers (one row per person, stored once) | `passenger_id` |
| `airport` | Airports, with a consistent code and name | `airport_code` |
| `calendar_date` | One row per date, with day of month and a business-day flag | `calendar_date` |
| `flight_schedule` | Planned flights: route, aircraft type, scheduled times | `flight_number` |
| `flight_leg` | A flown (or to-be-flown) occurrence of a scheduled flight, with actual times | `leg_id` |
| `flight_cost` | Cost of a flight for an aircraft type during a validity period | (`flight_number`, `aircraft_type_code`, `valid_from`) |
| `reservation` | A booking: main passenger, optional agent, status, ticket type, class, party size | `reservation_id` |
| `payment` | A payment: status, date, amount | `payment_id` |
| `reservation_payment` | Links reservations and payments (many-to-many) | (`reservation_id`, `payment_id`) |
| `reservation_leg` | Links reservations and legs (many-to-many) | (`reservation_id`, `leg_id`) |

### How the tables relate

- A **passenger** has zero or many **reservations**; every reservation has exactly one main passenger.
- A **booking agent** handles zero or many reservations; a reservation has zero or one agent (`agent_id` is nullable, so `NULL` means a direct booking).
- A **reservation** and a **payment** are many-to-many through `reservation_payment`.
- A **reservation** and a **flight leg** are many-to-many through `reservation_leg`.
- Every **flight leg** belongs to exactly one **flight schedule**; a schedule has zero or many legs.
- Every **flight schedule** and every **flight leg** has one origin and one destination **airport**; an airport can be referenced many times.
- A **flight schedule** has zero or many **flight cost** records; each cost record also references two dates in **calendar_date** (`valid_from`, `valid_to`).

### Deletion rules

| Relationship | Rule | Meaning |
|---|---|---|
| reservation → passenger | `RESTRICT` | A passenger with reservations cannot be deleted |
| reservation → booking_agent | `RESTRICT` | An agent with reservations cannot be deleted |
| schedule / leg → airport | `RESTRICT` | An airport in use cannot be deleted |
| leg → schedule | `RESTRICT` | A schedule with legs cannot be deleted |
| flight_cost → schedule, calendar_date | `RESTRICT` | Cost history keeps its schedule and dates |
| reservation_payment / reservation_leg → reservation | `CASCADE` | Deleting a reservation removes only its link rows |
| reservation_payment → payment | `RESTRICT` | A payment still linked to a reservation cannot be deleted |
| reservation_leg → flight_leg | `RESTRICT` | A leg still linked to a reservation cannot be deleted |

Removing a link row (a pair in a linking table) never deletes the payment or leg itself. `ON UPDATE RESTRICT` is used on airport and calendar-date references because MySQL 8 does not allow a `CHECK` constraint on a column whose foreign key uses `ON UPDATE CASCADE`; airport codes and dates never change in practice.

### Constraints and indexes

- **Validation (CHECK):** party size > 0; payment amount > 0; origin and destination differ (schedule and leg); scheduled arrival after departure; actual arrival after actual departure when both are known; `valid_to >= valid_from`; cost amount >= 0; calendar day of month matches the date.
- **Required vs nullable:** `second_name`, `agent_id`, `actual_departure` and `actual_arrival` are nullable; everything else that identifies a record is `NOT NULL`.
- **Indexes:** passenger name and email, schedule departure, leg flight number, reservation creation date, payment date, cost `valid_to`, plus the indexes MySQL creates for foreign keys and the primary keys.
- **Engine:** every table is InnoDB (foreign keys and transactions).
- **Time convention:** all `DATETIME` values are stored in **UTC**.

---

## Design explanations

### Why two linking tables are necessary
Both relationships are many-to-many. A reservation can have several payments, and one payment can cover several reservations. A reservation can include several legs, and a leg is shared by many reservations. A foreign key column on either side cannot represent that without repeating data or storing lists in one column. A linking table holds one row per pair, with a composite primary key that also blocks duplicate pairs.

### Why scheduled and actual times are separate
The spreadsheet overwrote planned times with actual times, so the plan was lost. Here `flight_schedule` keeps the plan (`scheduled_departure`, `scheduled_arrival`) and `flight_leg` records what happened (`actual_departure`, `actual_arrival`). The actual columns are nullable because they are unknown before a flight operates. Delays are the difference between the two.

### Why flight costs use a composite key
A cost depends on the flight, the aircraft type used, and the period in which the price applies. The key (`flight_number`, `aircraft_type_code`, `valid_from`) identifies one cost record. A price change adds a new row with a new `valid_from` instead of overwriting the old one, which preserves cost history. Both validity dates reference `calendar_date`.

### Simplifying assumption: flight number as schedule identifier
The schema treats `flight_number` as unique for one schedule. A real airline reuses a flight number every day (and on many days of the week), so a production system would identify an operating flight by a combination such as **airline + flight number + departure date (or schedule effective period)** and usually also the origin. It would also handle codeshares, route changes and aircraft swaps. For this project, a unique flight number keeps the model simple.

### Reference codes
Airline, aircraft type, reservation and payment status, ticket type and travel class are treated as **externally managed codes**. They are plain columns with no local reference tables and no foreign keys. The values in the seed data (for example `HW`, `A320`, `CONFIRMED`, `ONE_WAY`, `ECONOMY`) are **demonstration data**.

---

## Advantages and trade-offs

**Advantages**
- Each fact is stored once (a passenger's details are not repeated per reservation).
- Airports are referenced by code, so names cannot drift between rows.
- Planned and actual times, and old and new costs, coexist.
- Constraints (keys, checks, foreign keys, composite keys) stop invalid data at the database level.
- Linking tables allow shared payments and shared legs without duplication.

**Trade-offs**
- More tables mean more joins to see a complete reservation.
- Joining payments and legs together in one query multiplies rows and inflates totals, so queries must aggregate carefully (see below).
- Strict `RESTRICT` rules keep data safe but require users to remove links first before deleting records.

## Known limitations

1. **Shared payments do not reveal the exact amount allocated to each reservation.** The linking table has no allocation column, as required. If one payment covers three reservations, the database cannot say how much belongs to each. Only the payment total is known.
2. **Party size does not identify every traveler.** Only the main passenger and the number in the party are stored.
3. **Separating data reduces duplication but requires joins.** Reading one reservation touches several tables.
4. **Cost validity periods need an overlap policy.** The primary key stops duplicate start dates but does not stop two periods for the same flight and aircraft type from overlapping. A policy is needed (for example: periods must not overlap, enforced by the application or a trigger, or the most recent `valid_from` wins). The seed data uses consecutive, non-overlapping periods, and query E6 in `02_example_queries.sql` detects overlaps.
5. The generated data does not guarantee that a reservation's legs form a connected itinerary (each leg starting where the previous one ended).

---

## Example queries

All of these are in `database/02_example_queries.sql`.

1. **View a reservation with its passenger, agent, payments and legs** (queries 1a to 1c, plus 1d for a one-row-per-reservation summary).
2. **Find reservations using a particular leg** (query 2).
3. **Find payments linked to a reservation** (query 3).
4. **Find a flight cost for a flight, aircraft type and date** (query 4).

Example, reservation summary without inflated totals:

```sql
SELECT r.reservation_id,
       COALESCE(pt.total_paid, 0) AS total_paid,
       COALESCE(lt.leg_count, 0)  AS leg_count
FROM reservation r
LEFT JOIN (SELECT rp.reservation_id, SUM(pay.payment_amount) AS total_paid
           FROM reservation_payment rp
           JOIN payment pay ON pay.payment_id = rp.payment_id
           GROUP BY rp.reservation_id) pt ON pt.reservation_id = r.reservation_id
LEFT JOIN (SELECT reservation_id, COUNT(*) AS leg_count
           FROM reservation_leg
           GROUP BY reservation_id) lt ON lt.reservation_id = r.reservation_id;
```

**Avoiding inflated payment totals:** joining a reservation to both its payments and its legs gives one row per payment-leg combination, so a payment would be summed once per leg. The queries above aggregate payments and legs in separate subqueries (or list them in separate result sets) before combining them. Query E7 shows the inflated total next to the correct one.

## Developer notes
- To use this database from the CRUD app (Part 2), run the steps in **Quick start** and point the app's configuration at the same database.
- If you change the schema, update `01_schema.sql`, the Workbench model, and re-run the seed script.
