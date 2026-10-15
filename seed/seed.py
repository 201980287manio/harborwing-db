"""
HarborWing Air - synthetic data generator (IT8 Midterm Drill / Part 1)

Usage (from the seed/ folder, after running database/01_schema.sql):
    python seed.py

Repeatable: a fixed seed (SEED) is used, and every run first empties all
tables (TRUNCATE with foreign key checks off), so running it twice gives
the same data.

All people, companies, addresses and codes are fictional. Codes for
airlines, aircraft types, statuses, ticket types and travel classes are
DEMONSTRATION DATA (externally managed in a real system).
All DATETIME values are UTC.
"""
import os
import random
import string
import sys
from datetime import date, datetime, timedelta

import mysql.connector
from dotenv import load_dotenv
from faker import Faker

# ---------------------------------------------------------------- settings
SEED = 42
REF_NOW = datetime(2026, 10, 15, 0, 0, 0)  # fixed "today" so output is repeatable

N_AGENTS = 55
N_PASSENGERS = 120
N_AIRPORTS = 60
N_SCHEDULES = 80
N_LEGS = 120
N_RESERVATIONS = 150
N_PAYMENTS = 140

CAL_START = date(2026, 1, 1)
CAL_END = date(2027, 12, 31)

# DEMONSTRATION codes (externally managed in a real system)
AIRLINE_CODE = "HW"
AIRCRAFT_TYPES = ["AT72", "DH8D", "E175", "B738", "A320"]
RESERVATION_STATUS = ["CONFIRMED", "PENDING", "CANCELLED", "CHECKED_IN"]
PAYMENT_STATUS = ["PAID", "PENDING", "REFUNDED", "FAILED"]
TICKET_TYPES = ["ONE_WAY", "ROUND_TRIP", "MULTI_CITY"]
TRAVEL_CLASSES = ["ECONOMY", "PREMIUM", "BUSINESS"]

# Insert order: parents first. Reverse order is used for counting/reset.
TABLES = [
    "booking_agent", "passenger", "airport", "calendar_date",
    "flight_schedule", "flight_leg", "flight_cost",
    "reservation", "payment", "reservation_payment", "reservation_leg",
]


# ----------------------------------------------------------------- helpers
def rand_dt(start, end):
    """Random datetime on a 5-minute grid between start and end."""
    steps = int((end - start).total_seconds() // 300)
    return start + timedelta(minutes=5 * random.randint(0, steps))


def make_airport_codes(n):
    codes = set()
    while len(codes) < n:
        codes.add("".join(random.choices(string.ascii_uppercase, k=3)))
    return sorted(codes)


def insert(cur, table, columns, rows):
    placeholders = ", ".join(["%s"] * len(columns))
    sql = f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({placeholders})"
    cur.executemany(sql, rows)
    print(f"  inserted {len(rows):>4} rows into {table}")


def connect():
    load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "127.0.0.1"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", ""),
        database=os.getenv("DB_NAME", "harborwing_air"),
    )


# -------------------------------------------------------------------- main
def main():
    random.seed(SEED)
    Faker.seed(SEED)
    fake = Faker("en_US")

    conn = connect()
    cur = conn.cursor()
    try:
        # ------------------------------------------------------- reset
        print("Resetting tables...")
        cur.execute("SET FOREIGN_KEY_CHECKS = 0")
        for t in reversed(TABLES):
            cur.execute(f"TRUNCATE TABLE {t}")
        cur.execute("SET FOREIGN_KEY_CHECKS = 1")

        print("Seeding...")

        # ------------------------------------------------ booking agents
        agents = [
            (fake.company()[:120], f"Demo agency. {fake.catch_phrase()}"[:255])
            for _ in range(N_AGENTS)
        ]
        insert(cur, "booking_agent", ["agent_name", "other_details"], agents)

        # ---------------------------------------------------- passengers
        passengers = []
        for _ in range(N_PASSENGERS):
            second = fake.first_name() if random.random() < 0.4 else None
            addr2 = fake.secondary_address() if random.random() < 0.3 else None
            passengers.append((
                fake.first_name(), second, fake.last_name(),
                fake.phone_number()[:30], fake.safe_email(),
                fake.street_address()[:150], addr2,
                fake.city(), fake.state(), fake.country()[:100],
                "Fictional passenger (demonstration data)",
            ))
        insert(cur, "passenger", [
            "first_name", "second_name", "last_name", "phone", "email",
            "address_line1", "address_line2", "city", "state_province_county",
            "country", "other_details"], passengers)

        # ------------------------------------------------------ airports
        codes = make_airport_codes(N_AIRPORTS)
        airports = []
        for code in codes:
            city = fake.city()
            kind = random.choice(["International", "Regional", "Island", "Harbor"])
            airports.append((
                code, f"{city} {kind} Airport", city, fake.state(),
                fake.country()[:100], "Fictional airport (demonstration data)",
            ))
        insert(cur, "airport", [
            "airport_code", "airport_name", "city", "state_province_county",
            "country", "other_details"], airports)

        # ------------------------------------------------------ calendar
        calendar = []
        d = CAL_START
        while d <= CAL_END:
            calendar.append((d, d.day, 1 if d.weekday() < 5 else 0))
            d += timedelta(days=1)
        insert(cur, "calendar_date",
               ["calendar_date", "day_of_month", "is_business_day"], calendar)

        # ---------------------------------------------- flight schedules
        schedules = []  # dicts, so legs and costs can reuse the values
        for i in range(N_SCHEDULES):
            origin, dest = random.sample(codes, 2)
            dep = rand_dt(datetime(2026, 8, 1, 5, 0), datetime(2026, 12, 31, 22, 0))
            arr = dep + timedelta(minutes=random.randint(45, 240))
            schedules.append({
                "flight_number": f"{AIRLINE_CODE}{101 + i}",
                "aircraft": random.choice(AIRCRAFT_TYPES),
                "origin": origin, "dest": dest, "dep": dep, "arr": arr,
            })
        insert(cur, "flight_schedule", [
            "flight_number", "airline_code", "aircraft_type_code",
            "origin_airport_code", "destination_airport_code",
            "scheduled_departure", "scheduled_arrival"],
            [(s["flight_number"], AIRLINE_CODE, s["aircraft"], s["origin"],
              s["dest"], s["dep"], s["arr"]) for s in schedules])

        # -------------------------------------------------- flight legs
        # Every schedule gets one leg; extra legs are later repeats of a
        # schedule (shifted by whole weeks). Actual times are NULL when the
        # leg has not operated yet (after REF_NOW).
        sched_for_leg = list(range(N_SCHEDULES)) + [
            random.randrange(N_SCHEDULES) for _ in range(N_LEGS - N_SCHEDULES)
        ]
        occurrence = {}
        legs = []
        for si in sched_for_leg:
            k = occurrence.get(si, 0)
            occurrence[si] = k + 1
            s = schedules[si]
            dep = s["dep"] + timedelta(days=7 * k)
            duration = s["arr"] - s["dep"]
            if dep + duration < REF_NOW:
                a_dep = dep + timedelta(minutes=random.randint(-5, 45))
                a_arr = a_dep + duration + timedelta(minutes=random.randint(-10, 20))
            else:
                a_dep = a_arr = None
            legs.append((s["flight_number"], s["origin"], s["dest"], a_dep, a_arr))
        insert(cur, "flight_leg", [
            "flight_number", "origin_airport_code", "destination_airport_code",
            "actual_departure", "actual_arrival"], legs)

        # -------------------------------------------------- flight costs
        # 1-3 consecutive, non-overlapping validity periods per schedule,
        # plus an extra record for an alternate aircraft on some flights.
        costs = []
        for s in schedules:
            start = date(2026, 7, 1) + timedelta(days=random.randint(0, 60))
            for _ in range(random.choices([1, 2, 3], weights=[30, 45, 25])[0]):
                end = start + timedelta(days=random.randint(30, 120) - 1)
                costs.append((s["flight_number"], s["aircraft"], start, end,
                              round(random.uniform(2500, 9000), 2)))
                start = end + timedelta(days=1)
            if random.random() < 0.15:
                alt = random.choice([a for a in AIRCRAFT_TYPES if a != s["aircraft"]])
                a_start = date(2026, 7, 1)
                costs.append((s["flight_number"], alt, a_start,
                              a_start + timedelta(days=59),
                              round(random.uniform(2500, 9000), 2)))
        insert(cur, "flight_cost", [
            "flight_number", "aircraft_type_code", "valid_from", "valid_to",
            "cost_amount"], costs)

        # ------------------------------------------------ reservations
        reservations = []
        for _ in range(N_RESERVATIONS):
            agent = random.randint(1, N_AGENTS) if random.random() < 0.65 else None
            reservations.append((
                random.randint(1, N_PASSENGERS), agent,
                random.choice(RESERVATION_STATUS), random.choice(TICKET_TYPES),
                random.choice(TRAVEL_CLASSES),
                rand_dt(datetime(2026, 5, 1), datetime(2026, 10, 14)),
                random.choices(range(1, 7), weights=[40, 25, 15, 10, 6, 4])[0],
            ))
        insert(cur, "reservation", [
            "passenger_id", "agent_id", "status_code", "ticket_type_code",
            "travel_class_code", "created_at", "party_size"], reservations)

        # ----------------------------------------------------- payments
        payments = [(
            random.choice(PAYMENT_STATUS),
            rand_dt(datetime(2026, 6, 1), datetime(2026, 10, 15)),
            round(random.uniform(60, 1800), 2),
        ) for _ in range(N_PAYMENTS)]
        insert(cur, "payment",
               ["status_code", "payment_date", "payment_amount"], payments)

        # ------------------------------------- reservation <-> payment
        rp = set()
        for pid in range(1, N_PAYMENTS + 1):            # no orphan payments
            rp.add((random.randint(1, N_RESERVATIONS), pid))
        for pid in random.sample(range(1, N_PAYMENTS + 1), 30):   # shared payments
            for rid in random.sample(range(1, N_RESERVATIONS + 1), random.choice([1, 2])):
                rp.add((rid, pid))
        for rid in random.sample(range(1, N_RESERVATIONS + 1), 40):  # several payments
            for pid in random.sample(range(1, N_PAYMENTS + 1), random.randint(1, 3)):
                rp.add((rid, pid))
        covered = {r for r, _ in rp}
        for rid in range(1, N_RESERVATIONS + 1):         # every reservation has one
            if rid not in covered:
                rp.add((rid, random.randint(1, N_PAYMENTS)))
        insert(cur, "reservation_payment", ["reservation_id", "payment_id"],
               sorted(rp))

        # ------------------------------------------- reservation <-> leg
        rl = set()
        for rid in range(1, N_RESERVATIONS + 1):
            n = random.choices([1, 2, 3, 4], weights=[40, 35, 18, 7])[0]
            for lid in random.sample(range(1, N_LEGS + 1), n):
                rl.add((rid, lid))
        insert(cur, "reservation_leg", ["reservation_id", "leg_id"], sorted(rl))

        conn.commit()

        # --------------------------------------------------- verification
        print("\nRow counts:")
        ok = True
        for t in TABLES:
            cur.execute(f"SELECT COUNT(*) FROM {t}")
            n = cur.fetchone()[0]
            flag = "OK" if n >= 50 else "TOO FEW"
            ok = ok and n >= 50
            print(f"  {t:<22}{n:>6}  {flag}")
        print("\nAll tables have at least 50 rows." if ok
              else "\nWARNING: at least one table has fewer than 50 rows.")

    except Exception as exc:
        conn.rollback()
        print(f"\nSeeding failed, rolled back: {exc}", file=sys.stderr)
        raise
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()
