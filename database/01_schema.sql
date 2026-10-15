-- HarborWing Air database
-- IT8 Midterm Drill / Part 1
--
-- Run this file against an existing, empty database (e.g. harborwing_air).
-- It is safe to re-run: the block below drops all tables first (reset).
--
-- Externally managed codes (no local reference tables, no foreign keys):
--   airline_code, aircraft_type_code, status_code (reservation and payment),
--   ticket_type_code, travel_class_code
--
-- All DATETIME values are stored in UTC.
--
-- Deletion rules:
--   RESTRICT : parent rows cannot be deleted while child rows reference them
--   CASCADE  : only on reservation_payment / reservation_leg when the
--              RESERVATION is deleted (the link row has no meaning alone)
--   Deleting a payment or leg that is still linked is blocked (RESTRICT).
-- ON UPDATE RESTRICT is used on columns that also have CHECK constraints
-- (MySQL 8 does not allow CHECK on columns with ON UPDATE CASCADE).

-- ---------------------------------------------------------------
-- RESET
-- ---------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS reservation_leg, reservation_payment, flight_cost,
    payment, reservation, flight_leg, flight_schedule,
    calendar_date, airport, passenger, booking_agent;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------
-- TABLES
-- ---------------------------------------------------------------
CREATE TABLE booking_agent (
    agent_id INT AUTO_INCREMENT PRIMARY KEY,
    agent_name VARCHAR(120) NOT NULL,
    other_details VARCHAR(255)
) ENGINE=InnoDB;

CREATE TABLE passenger (
    passenger_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(80) NOT NULL,
    second_name VARCHAR(80) NULL,
    last_name VARCHAR(80) NOT NULL,
    phone VARCHAR(30),
    email VARCHAR(150),
    address_line1 VARCHAR(150),
    address_line2 VARCHAR(150),
    city VARCHAR(100),
    state_province_county VARCHAR(100),
    country VARCHAR(100),
    other_details TEXT,
    INDEX idx_passenger_name (last_name, first_name),
    INDEX idx_passenger_email (email)
) ENGINE=InnoDB;

CREATE TABLE airport (
    airport_code CHAR(3) PRIMARY KEY,
    airport_name VARCHAR(150) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_province_county VARCHAR(100),
    country VARCHAR(100) NOT NULL,
    other_details TEXT
) ENGINE=InnoDB;

CREATE TABLE calendar_date (
    calendar_date DATE PRIMARY KEY,
    day_of_month TINYINT UNSIGNED NOT NULL,
    is_business_day BOOLEAN NOT NULL,
    CHECK (
        day_of_month BETWEEN 1 AND 31
        AND day_of_month = DAYOFMONTH(calendar_date)
    )
) ENGINE=InnoDB;

CREATE TABLE flight_schedule (
    flight_number VARCHAR(15) PRIMARY KEY,
    airline_code VARCHAR(10) NOT NULL,
    aircraft_type_code VARCHAR(20) NOT NULL,
    origin_airport_code CHAR(3) NOT NULL,
    destination_airport_code CHAR(3) NOT NULL,
    scheduled_departure DATETIME NOT NULL,
    scheduled_arrival DATETIME NOT NULL,

    CONSTRAINT fk_schedule_origin
        FOREIGN KEY (origin_airport_code)
        REFERENCES airport(airport_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_schedule_destination
        FOREIGN KEY (destination_airport_code)
        REFERENCES airport(airport_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT chk_schedule_airports
        CHECK (origin_airport_code <> destination_airport_code),

    CONSTRAINT chk_schedule_times
        CHECK (scheduled_arrival > scheduled_departure),

    INDEX idx_schedule_departure (scheduled_departure)
) ENGINE=InnoDB;

CREATE TABLE flight_leg (
    leg_id INT AUTO_INCREMENT PRIMARY KEY,
    flight_number VARCHAR(15) NOT NULL,
    origin_airport_code CHAR(3) NOT NULL,
    destination_airport_code CHAR(3) NOT NULL,
    actual_departure DATETIME NULL,
    actual_arrival DATETIME NULL,

    CONSTRAINT fk_leg_schedule
        FOREIGN KEY (flight_number)
        REFERENCES flight_schedule(flight_number)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT fk_leg_origin
        FOREIGN KEY (origin_airport_code)
        REFERENCES airport(airport_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_leg_destination
        FOREIGN KEY (destination_airport_code)
        REFERENCES airport(airport_code)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT chk_leg_airports
        CHECK (origin_airport_code <> destination_airport_code),

    CONSTRAINT chk_leg_actual_times
        CHECK (
            actual_departure IS NULL
            OR actual_arrival IS NULL
            OR actual_arrival > actual_departure
        ),

    INDEX idx_leg_flight (flight_number)
) ENGINE=InnoDB;

CREATE TABLE reservation (
    reservation_id INT AUTO_INCREMENT PRIMARY KEY,
    passenger_id INT NOT NULL,
    agent_id INT NULL,
    status_code VARCHAR(30) NOT NULL,
    ticket_type_code VARCHAR(30) NOT NULL,
    travel_class_code VARCHAR(30) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    party_size INT NOT NULL,

    CONSTRAINT fk_reservation_passenger
        FOREIGN KEY (passenger_id)
        REFERENCES passenger(passenger_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT fk_reservation_agent
        FOREIGN KEY (agent_id)
        REFERENCES booking_agent(agent_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT chk_reservation_party_size
        CHECK (party_size > 0),

    INDEX idx_reservation_created (created_at)
) ENGINE=InnoDB;

CREATE TABLE payment (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    status_code VARCHAR(30) NOT NULL,
    payment_date DATETIME NOT NULL,
    payment_amount DECIMAL(12,2) NOT NULL,

    CONSTRAINT chk_payment_amount
        CHECK (payment_amount > 0),

    INDEX idx_payment_date (payment_date)
) ENGINE=InnoDB;

CREATE TABLE flight_cost (
    flight_number VARCHAR(15) NOT NULL,
    aircraft_type_code VARCHAR(20) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    cost_amount DECIMAL(12,2) NOT NULL,

    PRIMARY KEY (flight_number, aircraft_type_code, valid_from),

    CONSTRAINT fk_cost_flight
        FOREIGN KEY (flight_number)
        REFERENCES flight_schedule(flight_number)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT fk_cost_valid_from
        FOREIGN KEY (valid_from)
        REFERENCES calendar_date(calendar_date)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_cost_valid_to
        FOREIGN KEY (valid_to)
        REFERENCES calendar_date(calendar_date)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT chk_cost_dates
        CHECK (valid_to >= valid_from),

    CONSTRAINT chk_cost_amount
        CHECK (cost_amount >= 0),

    INDEX idx_cost_valid_to (valid_to)
) ENGINE=InnoDB;

CREATE TABLE reservation_payment (
    reservation_id INT NOT NULL,
    payment_id INT NOT NULL,

    PRIMARY KEY (reservation_id, payment_id),

    CONSTRAINT fk_rp_reservation
        FOREIGN KEY (reservation_id)
        REFERENCES reservation(reservation_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_rp_payment
        FOREIGN KEY (payment_id)
        REFERENCES payment(payment_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE reservation_leg (
    reservation_id INT NOT NULL,
    leg_id INT NOT NULL,

    PRIMARY KEY (reservation_id, leg_id),

    CONSTRAINT fk_rl_reservation
        FOREIGN KEY (reservation_id)
        REFERENCES reservation(reservation_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_rl_leg
        FOREIGN KEY (leg_id)
        REFERENCES flight_leg(leg_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
