//! Specs for `web::email::stalwart_receiving_enabled` -- the gate on whether the internal-only
//! `POST :27705/email` MTA Hook endpoint accepts mail at all (see that module's own doc and
//! `docs/contact_integrations.md`'s Email section). Lives here (not in `web/email.rs` itself)
//! because `src/tests` (and its `crate::tests::factories` helpers) is only ever compiled into the
//! `rellm` lib target, but `web/email.rs` is also compiled as part of `main.rs`'s own duplicate
//! module tree for the `rellm` bin -- a test there can't reach `crate::tests::factories`.

use diesel::prelude::*;

use crate::models;
use crate::protos::StalwartConfig;
use crate::schema::server_configurations;
use crate::tests::factories::*;
use crate::web::email::stalwart_receiving_enabled;

#[test]
fn stalwart_receiving_enabled_is_false_when_never_configured() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        // No `server_configurations` row at all -- `get_server_configuration_model` falls back to
        // `create_default_server_configuration`, whose `stalwart_config` is `None`.
        assert!(!stalwart_receiving_enabled(conn));
        Ok(())
    });
}

#[test]
fn stalwart_receiving_enabled_is_false_when_present_but_disabled() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let mut new_config = models::default_server_configuration();
        new_config.stalwart_config =
            Some(serde_json::to_value(StalwartConfig { stalwart_receiving_enabled: false }).unwrap());
        diesel::insert_into(server_configurations::table)
            .values(&new_config)
            .execute(conn)
            .expect("failed to create test server configuration");

        assert!(!stalwart_receiving_enabled(conn));
        Ok(())
    });
}

#[test]
fn stalwart_receiving_enabled_is_true_once_enabled() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let mut new_config = models::default_server_configuration();
        new_config.stalwart_config =
            Some(serde_json::to_value(StalwartConfig { stalwart_receiving_enabled: true }).unwrap());
        diesel::insert_into(server_configurations::table)
            .values(&new_config)
            .execute(conn)
            .expect("failed to create test server configuration");

        assert!(stalwart_receiving_enabled(conn));
        Ok(())
    });
}
