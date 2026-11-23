BEGIN;

SET LOCAL search_path = public, pg_catalog;

CREATE TYPE schedule_approval_status AS ENUM ('pending_admin', 'approved', 'rejected');

CREATE TYPE booking_status AS ENUM ('reserved', 'confirmed', 'cancelled', 'completed', 'no_show');

CREATE TABLE organizations (
    id SERIAL NOT NULL,
    owner_id INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    subscription_active BOOLEAN NOT NULL DEFAULT true,
    PRIMARY KEY(id)
);

CREATE TABLE locations (
    id SERIAL NOT NULL,
    organization_id INTEGER NOT NULL,
    address TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    admin_phone VARCHAR(20) NOT NULL,
    PRIMARY KEY(id)
);

CREATE TABLE master_profiles (
    id SERIAL NOT NULL,
    user_id INTEGER NOT NULL UNIQUE,
    bio TEXT,
    photo_path VARCHAR(255),
    PRIMARY KEY(id)
);

CREATE TABLE master_locations (
    master_id INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    job_title VARCHAR(100),
    started_on DATE NOT NULL,
    PRIMARY KEY(master_id, location_id)
);

CREATE TABLE services (
    id SERIAL NOT NULL,
    location_id INTEGER NOT NULL,
    name VARCHAR(255) NOT NULL,
    price INTEGER NOT NULL,
    duration_minutes INTEGER NOT NULL,
    PRIMARY KEY(id)
);

CREATE TABLE booking_sources (
    id SERIAL NOT NULL,
    name VARCHAR(100) NOT NULL,
    created_by_user_id INTEGER,
    organization_id INTEGER,
    PRIMARY KEY(id),
    CONSTRAINT booking_sources_name_check CHECK (name <> '' AND name = btrim(name))
);

CREATE UNIQUE INDEX booking_sources_organization_name_uidx
    ON booking_sources (organization_id, lower(name)) NULLS NOT DISTINCT;

CREATE TABLE schedules (
    id SERIAL NOT NULL,
    master_id INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    work_date DATE NOT NULL,
    shift_start TIME NOT NULL,
    shift_end TIME NOT NULL,
    approval_status schedule_approval_status NOT NULL DEFAULT 'pending_admin',
    created_by_user_id INTEGER,
    PRIMARY KEY(id)
);

CREATE TABLE bookings (
    id SERIAL NOT NULL,
    schedule_id INTEGER NOT NULL,
    master_id INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    service_id INTEGER NOT NULL,
    client_id INTEGER,
    client_name VARCHAR(100),
    client_phone VARCHAR(20),
    starts_at TIMESTAMP NOT NULL,
    ends_at TIMESTAMP NOT NULL,
    status booking_status NOT NULL DEFAULT 'confirmed',
    reserved_until TIMESTAMPTZ,
    source_id INTEGER,
    created_by_user_id INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(id)
);

CREATE TABLE roles (
    id SERIAL NOT NULL,
    name VARCHAR(50) NOT NULL UNIQUE CHECK (name IN ('client', 'master', 'admin', 'superadmin')),
    PRIMARY KEY(id)
);

CREATE TABLE users (
    id SERIAL NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    last_name VARCHAR(100),
    first_name VARCHAR(100),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(id)
);

CREATE TABLE user_roles (
    user_id INTEGER NOT NULL,
    role_id INTEGER NOT NULL,
    PRIMARY KEY(user_id, role_id)
);

CREATE TABLE master_services (
    master_id INTEGER NOT NULL,
    service_id INTEGER NOT NULL,
    PRIMARY KEY(master_id, service_id)
);

CREATE TABLE location_admins (
    user_id INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    PRIMARY KEY(user_id, location_id)
);

ALTER TABLE organizations
    ADD FOREIGN KEY (owner_id) REFERENCES users (id);

ALTER TABLE locations
    ADD FOREIGN KEY (organization_id) REFERENCES organizations (id);

ALTER TABLE master_profiles
    ADD FOREIGN KEY (user_id) REFERENCES users (id);

ALTER TABLE master_locations
    ADD FOREIGN KEY (master_id) REFERENCES master_profiles (id);

ALTER TABLE master_locations
    ADD FOREIGN KEY (location_id) REFERENCES locations (id);

ALTER TABLE services
    ADD FOREIGN KEY (location_id) REFERENCES locations (id);

ALTER TABLE master_services
    ADD FOREIGN KEY (master_id) REFERENCES master_profiles (id);

ALTER TABLE master_services
    ADD FOREIGN KEY (service_id) REFERENCES services (id);

ALTER TABLE schedules
    ADD FOREIGN KEY (master_id) REFERENCES master_profiles (id);

ALTER TABLE schedules
    ADD FOREIGN KEY (location_id) REFERENCES locations (id);

ALTER TABLE schedules
    ADD FOREIGN KEY (created_by_user_id) REFERENCES users (id);

ALTER TABLE bookings
    ADD FOREIGN KEY (schedule_id) REFERENCES schedules (id);

ALTER TABLE bookings
    ADD FOREIGN KEY (master_id) REFERENCES master_profiles (id);

ALTER TABLE bookings
    ADD FOREIGN KEY (location_id) REFERENCES locations (id);

ALTER TABLE bookings
    ADD FOREIGN KEY (service_id) REFERENCES services (id);

ALTER TABLE bookings
    ADD FOREIGN KEY (client_id) REFERENCES users (id);

ALTER TABLE bookings
    ADD FOREIGN KEY (created_by_user_id) REFERENCES users (id);

ALTER TABLE bookings
    ADD FOREIGN KEY (source_id) REFERENCES booking_sources (id);

ALTER TABLE booking_sources
    ADD FOREIGN KEY (created_by_user_id) REFERENCES users (id),
    ADD FOREIGN KEY (organization_id) REFERENCES organizations (id);

ALTER TABLE user_roles
    ADD FOREIGN KEY (role_id) REFERENCES roles (id);

ALTER TABLE user_roles
    ADD FOREIGN KEY (user_id) REFERENCES users (id);

ALTER TABLE location_admins
    ADD FOREIGN KEY (user_id) REFERENCES users (id);

ALTER TABLE location_admins
    ADD FOREIGN KEY (location_id) REFERENCES locations (id);

INSERT INTO roles (name) VALUES ('client'), ('master'), ('admin'), ('superadmin');

INSERT INTO booking_sources (name) VALUES ('phone'), ('qr'), ('website'), ('app');

COMMENT ON COLUMN booking_sources.organization_id IS 'NULL means the source is shared by all organizations.';
COMMENT ON COLUMN services.price IS 'Service price in whole Russian rubles (RUB).';

COMMENT ON TABLE schedules IS 'Dated shifts for masters at a location.';

ALTER TABLE services
    ADD CONSTRAINT services_price_check CHECK (price >= 0),
    ADD CONSTRAINT services_duration_minutes_check CHECK (duration_minutes > 0),
    ADD CONSTRAINT services_id_location_id_key UNIQUE (id, location_id);

ALTER TABLE schedules
    ADD CONSTRAINT schedules_id_master_id_location_id_key UNIQUE (id, master_id, location_id),
    ADD CONSTRAINT schedules_master_id_location_id_fkey
        FOREIGN KEY (master_id, location_id) REFERENCES master_locations (master_id, location_id);

ALTER TABLE bookings
    ADD CONSTRAINT bookings_valid_interval_check CHECK (starts_at < ends_at),
    ADD CONSTRAINT bookings_reservation_expiry_check
        CHECK ((status = 'reserved') = (reserved_until IS NOT NULL)),
    ADD CONSTRAINT bookings_client_contact_check
        CHECK (status IN ('reserved', 'cancelled') OR (client_name IS NOT NULL AND client_phone IS NOT NULL)),
    ADD CONSTRAINT bookings_schedule_master_location_fkey
        FOREIGN KEY (schedule_id, master_id, location_id) REFERENCES schedules (id, master_id, location_id),
    ADD CONSTRAINT bookings_service_location_fkey
        FOREIGN KEY (service_id, location_id) REFERENCES services (id, location_id),
    ADD CONSTRAINT bookings_master_service_fkey
        FOREIGN KEY (master_id, service_id) REFERENCES master_services (master_id, service_id);

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_no_overlapping_active_intervals
        EXCLUDE USING gist (master_id WITH =, tsrange(starts_at, ends_at, '[)') WITH &&)
        WHERE (status IN ('reserved', 'confirmed'));

CREATE FUNCTION enforce_booking_reservation() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $reservation$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'reserved' AND NEW.status NOT IN ('reserved', 'confirmed', 'cancelled') THEN
            RAISE EXCEPTION 'A reservation can only be confirmed or cancelled' USING ERRCODE = '23514';
        END IF;

        IF NEW.status = 'confirmed' AND (
            OLD.status = 'cancelled' OR
            (OLD.status = 'reserved' AND OLD.reserved_until <= clock_timestamp())
        ) THEN
            RAISE EXCEPTION 'An expired or cancelled reservation cannot be confirmed' USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.status = 'reserved' THEN
        IF TG_OP = 'INSERT' THEN
            NEW.reserved_until := clock_timestamp() + INTERVAL '10 minutes';
        ELSIF OLD.status = 'reserved' THEN
            NEW.reserved_until := OLD.reserved_until;
        ELSE
            RAISE EXCEPTION 'Create a new reservation for a new booking attempt' USING ERRCODE = '23514';
        END IF;
    ELSE
        NEW.reserved_until := NULL;
    END IF;

    -- Clear overlapping expired reservations so the exclusion index admits a new booking.
    IF NEW.status IN ('reserved', 'confirmed') THEN
        UPDATE public.bookings
        SET status = 'cancelled'
        WHERE id <> NEW.id
          AND master_id = NEW.master_id
          AND status = 'reserved'
          AND reserved_until <= clock_timestamp()
          AND starts_at < NEW.ends_at
          AND ends_at > NEW.starts_at;
    END IF;

    RETURN NEW;
END
$reservation$;

CREATE TRIGGER bookings_enforce_reservation
    BEFORE INSERT OR UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION enforce_booking_reservation();

CREATE VIEW active_booking_intervals AS
SELECT id AS booking_id, master_id, location_id, starts_at, ends_at
FROM bookings
WHERE status = 'confirmed'
   OR (status = 'reserved' AND reserved_until > statement_timestamp());

COMMIT;
