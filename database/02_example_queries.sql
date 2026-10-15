-- HarborWing Air: example queries
-- IT8 Midterm Drill / Part 1
--
-- Run each query on its own (select it, or paste one at a time).
-- Change the example IDs (reservation 1, leg 5, flight HW101) as you like.
--
-- IMPORTANT - avoiding inflated totals:
-- Joining a reservation to BOTH its payments and its legs in one query
-- multiplies rows (2 payments x 3 legs = 6 rows), so SUM(payment_amount)
-- would be counted several times. These queries avoid that by either
-- (a) listing payments and legs in separate result sets, or
-- (b) summarising each one in its own subquery before joining.

-- ---------------------------------------------------------------
-- 1a. One reservation with its passenger and agent (one row)
-- ---------------------------------------------------------------
SELECT r.reservation_id,
       r.status_code, r.ticket_type_code, r.travel_class_code,
       r.created_at, r.party_size,
       CONCAT_WS(' ', p.first_name, p.second_name, p.last_name) AS passenger_name,
       p.email, p.phone,
       COALESCE(a.agent_name, '(direct booking)') AS booking_agent
FROM reservation r
JOIN passenger p          ON p.passenger_id = r.passenger_id
LEFT JOIN booking_agent a ON a.agent_id = r.agent_id
WHERE r.reservation_id = 1;

-- 1b. The same reservation's payments (separate result, no multiplication)
SELECT pay.payment_id, pay.status_code, pay.payment_date, pay.payment_amount
FROM reservation_payment rp
JOIN payment pay ON pay.payment_id = rp.payment_id
WHERE rp.reservation_id = 1
ORDER BY pay.payment_date;

-- 1c. The same reservation's legs
SELECT l.leg_id, l.flight_number,
       l.origin_airport_code, l.destination_airport_code,
       s.scheduled_departure, s.scheduled_arrival,
       l.actual_departure, l.actual_arrival
FROM reservation_leg rl
JOIN flight_leg l       ON l.leg_id = rl.leg_id
JOIN flight_schedule s  ON s.flight_number = l.flight_number
WHERE rl.reservation_id = 1
ORDER BY COALESCE(l.actual_departure, s.scheduled_departure);

-- 1d. Summary of every reservation in ONE row each, safe totals
--     (payments and legs are aggregated separately, then joined)
SELECT r.reservation_id,
       CONCAT_WS(' ', p.first_name, p.last_name)   AS passenger_name,
       COALESCE(a.agent_name, '(direct booking)')  AS booking_agent,
       COALESCE(pt.payment_count, 0)               AS payment_count,
       COALESCE(pt.total_paid, 0)                  AS total_paid,
       COALESCE(lt.leg_count, 0)                   AS leg_count
FROM reservation r
JOIN passenger p          ON p.passenger_id = r.passenger_id
LEFT JOIN booking_agent a ON a.agent_id = r.agent_id
LEFT JOIN (SELECT rp.reservation_id,
                  COUNT(*)                AS payment_count,
                  SUM(pay.payment_amount) AS total_paid
           FROM reservation_payment rp
           JOIN payment pay ON pay.payment_id = rp.payment_id
           GROUP BY rp.reservation_id) pt ON pt.reservation_id = r.reservation_id
LEFT JOIN (SELECT reservation_id, COUNT(*) AS leg_count
           FROM reservation_leg
           GROUP BY reservation_id) lt ON lt.reservation_id = r.reservation_id
ORDER BY r.reservation_id
LIMIT 20;

-- ---------------------------------------------------------------
-- 2. Reservations that use a particular leg
-- ---------------------------------------------------------------
SELECT r.reservation_id, r.status_code, r.created_at, r.party_size,
       CONCAT_WS(' ', p.first_name, p.last_name) AS passenger_name
FROM reservation_leg rl
JOIN reservation r ON r.reservation_id = rl.reservation_id
JOIN passenger p   ON p.passenger_id = r.passenger_id
WHERE rl.leg_id = 5
ORDER BY r.reservation_id;

-- ---------------------------------------------------------------
-- 3. Payments linked to a reservation
--    (also shows which OTHER reservations share each payment)
-- ---------------------------------------------------------------
SELECT pay.payment_id, pay.status_code, pay.payment_date, pay.payment_amount,
       (SELECT COUNT(*) FROM reservation_payment x
        WHERE x.payment_id = pay.payment_id) AS reservations_sharing_payment
FROM reservation_payment rp
JOIN payment pay ON pay.payment_id = rp.payment_id
WHERE rp.reservation_id = 1
ORDER BY pay.payment_date;

-- ---------------------------------------------------------------
-- 4. Flight cost for a flight, aircraft type and date
--    A date is picked that is guaranteed to fall inside a cost period
--    of HW101, so the example always returns a row.
-- ---------------------------------------------------------------
SET @flight   = 'HW101';
SET @aircraft = (SELECT aircraft_type_code FROM flight_schedule
                 WHERE flight_number = @flight);
SET @on_date  = (SELECT DATE_ADD(MIN(valid_from), INTERVAL 5 DAY)
                 FROM flight_cost
                 WHERE flight_number = @flight AND aircraft_type_code = @aircraft);

SELECT fc.flight_number, fc.aircraft_type_code,
       fc.valid_from, fc.valid_to, fc.cost_amount
FROM flight_cost fc
WHERE fc.flight_number = @flight
  AND fc.aircraft_type_code = @aircraft
  AND @on_date BETWEEN fc.valid_from AND fc.valid_to;

-- ---------------------------------------------------------------
-- Extra checks useful for the explainer video
-- ---------------------------------------------------------------

-- E1. Direct vs agent-assisted reservations
SELECT CASE WHEN agent_id IS NULL THEN 'direct' ELSE 'agent-assisted' END AS booking_type,
       COUNT(*) AS reservations
FROM reservation
GROUP BY booking_type;

-- E2. Payments shared by more than one reservation
SELECT payment_id, COUNT(*) AS reservations_sharing
FROM reservation_payment
GROUP BY payment_id
HAVING COUNT(*) > 1
ORDER BY reservations_sharing DESC, payment_id
LIMIT 10;

-- E3. Reservations with several payments AND several legs
SELECT rp.reservation_id,
       COUNT(DISTINCT rp.payment_id) AS payments,
       COUNT(DISTINCT rl.leg_id)     AS legs
FROM reservation_payment rp
JOIN reservation_leg rl ON rl.reservation_id = rp.reservation_id
GROUP BY rp.reservation_id
HAVING payments > 1 AND legs > 1
ORDER BY payments DESC, legs DESC
LIMIT 10;

-- E4. Flights with more than one cost validity period
SELECT flight_number, COUNT(*) AS cost_periods,
       MIN(valid_from) AS first_valid_from, MAX(valid_to) AS last_valid_to
FROM flight_cost
GROUP BY flight_number
HAVING COUNT(*) > 1
ORDER BY cost_periods DESC, flight_number
LIMIT 10;

-- E5. Legs that have not operated yet (actual times unknown)
SELECT COUNT(*) AS legs_without_actual_times
FROM flight_leg
WHERE actual_departure IS NULL;

-- E6. Overlap check: cost periods overlapping for the same flight+aircraft
--     (the schema does not forbid overlaps; this finds them. Expect 0 rows.)
SELECT a.flight_number, a.aircraft_type_code,
       a.valid_from AS period_a_from, a.valid_to AS period_a_to,
       b.valid_from AS period_b_from, b.valid_to AS period_b_to
FROM flight_cost a
JOIN flight_cost b
  ON  a.flight_number = b.flight_number
  AND a.aircraft_type_code = b.aircraft_type_code
  AND a.valid_from < b.valid_from
  AND b.valid_from <= a.valid_to;

-- E7. Wrong way vs right way: total paid for reservation 1
--     WRONG: joining payments and legs together repeats each payment per leg.
SELECT r.reservation_id, SUM(pay.payment_amount) AS inflated_total
FROM reservation r
JOIN reservation_payment rp ON rp.reservation_id = r.reservation_id
JOIN payment pay            ON pay.payment_id = rp.payment_id
JOIN reservation_leg rl     ON rl.reservation_id = r.reservation_id
WHERE r.reservation_id = 1
GROUP BY r.reservation_id;
--     RIGHT: payments only, each counted once.
SELECT rp.reservation_id, SUM(pay.payment_amount) AS correct_total
FROM reservation_payment rp
JOIN payment pay ON pay.payment_id = rp.payment_id
WHERE rp.reservation_id = 1
GROUP BY rp.reservation_id;
