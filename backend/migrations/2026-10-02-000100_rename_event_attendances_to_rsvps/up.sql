-- Renames `event_attendances` to `rsvps` (see events.proto's EventAttendance -> Rsvp rename).
-- Purely a naming change -- no behavior change.

ALTER TABLE event_attendances RENAME CONSTRAINT event_attendances_pkey TO rsvps_pkey;
ALTER TABLE event_attendances RENAME CONSTRAINT event_attendances_occasion_id_fkey TO rsvps_occasion_id_fkey;
ALTER TABLE event_attendances RENAME CONSTRAINT event_attendances_user_id_fkey TO rsvps_user_id_fkey;
ALTER TABLE event_attendances RENAME CONSTRAINT event_attendances_inviting_user_id_fkey TO rsvps_inviting_user_id_fkey;
ALTER SEQUENCE event_attendances_id_seq RENAME TO rsvps_id_seq;
ALTER TABLE event_attendances RENAME TO rsvps;
