BEGIN;

SET LOCAL search_path = public, pg_catalog;

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
    coordinates VARCHAR(50) NOT NULL,
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
    PRIMARY KEY(id)
);

CREATE TABLE schedules (
    id SERIAL NOT NULL,
    master_id INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    work_date DATE NOT NULL,
    shift_start TIME NOT NULL,
    shift_end TIME NOT NULL,
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
    client_name VARCHAR(100) NOT NULL,
    client_phone VARCHAR(20) NOT NULL,
    starts_at TIMESTAMP NOT NULL,
    ends_at TIMESTAMP NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'created',
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
    ADD FOREIGN KEY (created_by_user_id) REFERENCES users (id);

ALTER TABLE user_roles
    ADD FOREIGN KEY (role_id) REFERENCES roles (id);

ALTER TABLE user_roles
    ADD FOREIGN KEY (user_id) REFERENCES users (id);

ALTER TABLE location_admins
    ADD FOREIGN KEY (user_id) REFERENCES users (id);

ALTER TABLE location_admins
    ADD FOREIGN KEY (location_id) REFERENCES locations (id);

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
    ADD CONSTRAINT bookings_schedule_master_location_fkey
        FOREIGN KEY (schedule_id, master_id, location_id) REFERENCES schedules (id, master_id, location_id),
    ADD CONSTRAINT bookings_service_location_fkey
        FOREIGN KEY (service_id, location_id) REFERENCES services (id, location_id),
    ADD CONSTRAINT bookings_master_service_fkey
        FOREIGN KEY (master_id, service_id) REFERENCES master_services (master_id, service_id);

-- Include the existing default status and the confirmed status in the conflict check.
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_no_overlapping_active_intervals
        EXCLUDE USING gist (master_id WITH =, tsrange(starts_at, ends_at, '[)') WITH &&)
        WHERE (status IN ('created', 'confirmed'));

COMMIT;
