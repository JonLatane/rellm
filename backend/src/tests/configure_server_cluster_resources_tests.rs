//! Specs for `configure_server`'s handling of `ClusterResources.conductor_state`: it must never be
//! forced into `Some(_)` by `ConfigureServer` itself -- only `LockClusterResources`/
//! `FreeClusterResources` (i.e. this instance actually being asked to broker a lock) may populate
//! it, since `Shared/Components.Pages.ServerInformationPage.ClusterTab.elm` takes a populated
//! `conductor_state` as "this instance IS the conductor" and shows its Held Locks/Limits sections
//! accordingly. Saving cluster settings that merely *point at* some other conductor must leave
//! `conductor_state` alone.

use diesel::*;

use crate::protos::*;
use crate::rpcs::{configure_server, get_server_configuration_proto};
use crate::tests::factories::*;

fn cluster_settings_request(
    conn: &mut crate::db_connection::PgPooledConnection,
    cluster_resources: Option<ClusterResources>,
) -> ServerConfiguration {
    let mut config = get_server_configuration_proto(conn).expect("failed to fetch base config");
    config.cluster_resources = cluster_resources;
    config
}

#[test]
fn pointing_at_a_remote_conductor_does_not_populate_conductor_state() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "csc_satellite");
        let admin = grant_permissions(
            conn,
            &admin,
            vec![Permission::Admin, Permission::EditClusterSettings],
        );

        let request = cluster_settings_request(
            conn,
            Some(ClusterResources {
                namespace_id: "my-satellite".to_string(),
                conductor_host: "conductor.example.com".to_string(),
                cluster_shared_secret: "shared-secret".to_string(),
                conductor_state: None,
            }),
        );

        let updated = configure_server(request, &admin, conn).expect("configure should succeed");

        let cluster_resources = updated.cluster_resources.expect("cluster_resources should be set");
        assert_eq!(cluster_resources.namespace_id, "my-satellite");
        assert_eq!(cluster_resources.conductor_host, "conductor.example.com");
        assert!(
            cluster_resources.conductor_state.is_none(),
            "merely pointing conductor_host at another instance must not make this one look like a conductor"
        );

        Ok(())
    });
}

#[test]
fn conductor_state_stays_none_across_repeated_saves() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "csc_satellite_repeat");
        let admin = grant_permissions(
            conn,
            &admin,
            vec![Permission::Admin, Permission::EditClusterSettings],
        );

        let first_request = cluster_settings_request(
            conn,
            Some(ClusterResources {
                namespace_id: "my-satellite".to_string(),
                conductor_host: "conductor.example.com".to_string(),
                cluster_shared_secret: "shared-secret".to_string(),
                conductor_state: None,
            }),
        );
        configure_server(first_request, &admin, conn).expect("first configure should succeed");

        // Re-fetching and re-saving (e.g. the admin editing the Namespace ID a second time)
        // shouldn't manufacture conductor_state out of nothing either -- it should still be
        // carried forward as `None` from the config `configure_server` itself just wrote.
        let second_request = cluster_settings_request(
            conn,
            Some(ClusterResources {
                namespace_id: "my-satellite-renamed".to_string(),
                conductor_host: "conductor.example.com".to_string(),
                cluster_shared_secret: String::new(),
                conductor_state: None,
            }),
        );
        let updated =
            configure_server(second_request, &admin, conn).expect("second configure should succeed");

        let cluster_resources = updated.cluster_resources.expect("cluster_resources should be set");
        assert_eq!(cluster_resources.namespace_id, "my-satellite-renamed");
        assert!(cluster_resources.conductor_state.is_none());

        Ok(())
    });
}

#[test]
fn limits_are_still_editable_once_this_instance_is_actually_a_conductor() {
    let mut conn = test_conn();
    conn.test_transaction::<_, tonic::Status, _>(|conn| {
        let admin = create_user(conn, "csc_conductor");
        let admin = grant_permissions(
            conn,
            &admin,
            vec![Permission::Admin, Permission::EditClusterSettings],
        );

        // Simulates this instance having already received a real LockClusterResources/
        // FreeClusterResources call at some point -- conductor_state is already `Some`, with a
        // held lock that ConfigureServer must never be able to touch.
        let existing_lock = ClusterResourceLock {
            lock_holder_namespace_id: "some-other-namespace".to_string(),
            resources: vec![ClusterResource::Ffmpeg as i32],
            acquired_at: None,
        };
        let seed_request = cluster_settings_request(
            conn,
            Some(ClusterResources {
                namespace_id: "the-conductor".to_string(),
                conductor_host: "conductor.example.com".to_string(),
                cluster_shared_secret: "shared-secret".to_string(),
                conductor_state: None,
            }),
        );
        configure_server(seed_request, &admin, conn).expect("seed configure should succeed");

        // Directly seed conductor_state the way LockClusterResources itself would -- ConfigureServer
        // itself can never do this (see the specs above), so this reaches past it on purpose.
        let with_state = get_server_configuration_proto(conn).unwrap();
        let mut cluster_resources = with_state.cluster_resources.clone().unwrap();
        cluster_resources.conductor_state = Some(ClusterConductorState {
            locks: vec![existing_lock.clone()],
            limits: vec![],
        });
        diesel::update(crate::schema::server_configurations::table)
            .set(crate::schema::server_configurations::cluster_resources.eq(serde_json::to_value(&cluster_resources).unwrap()))
            .execute(conn)
            .unwrap();

        let limits_request = cluster_settings_request(
            conn,
            Some(ClusterResources {
                namespace_id: "the-conductor".to_string(),
                conductor_host: "conductor.example.com".to_string(),
                cluster_shared_secret: String::new(),
                conductor_state: Some(ClusterConductorState {
                    locks: vec![],
                    limits: vec![ClusterResourceLimit {
                        resource: vec![ClusterResource::Ffmpeg as i32],
                        limit: vec![3],
                    }],
                }),
            }),
        );
        let updated =
            configure_server(limits_request, &admin, conn).expect("limits configure should succeed");

        let conductor_state = updated
            .cluster_resources
            .expect("cluster_resources should be set")
            .conductor_state
            .expect("conductor_state should stay populated once already a conductor");
        assert_eq!(
            conductor_state.limits,
            vec![ClusterResourceLimit {
                resource: vec![ClusterResource::Ffmpeg as i32],
                limit: vec![3],
            }]
        );
        assert_eq!(
            conductor_state.locks,
            vec![existing_lock],
            "locks must never be settable via ConfigureServer, even while editing limits"
        );

        Ok(())
    });
}
