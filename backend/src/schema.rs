// @generated automatically by Diesel CLI.

pub mod sql_types {
    #[derive(diesel::query_builder::QueryId, diesel::sql_types::SqlType)]
    #[diesel(postgres_type(name = "post_media_layout"))]
    pub struct PostMediaLayout;

    #[derive(diesel::query_builder::QueryId, diesel::sql_types::SqlType)]
    #[diesel(postgres_type(name = "recipient_type"))]
    pub struct RecipientType;

}

diesel::table! {
    ai_provider_grants (id) {
        id -> Int8,
        ai_provider_id -> Int8,
        grantee_id -> Int8,
        model_names -> Array<Varchar>,
        tokens_remaining -> Int8,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
        overage -> Int8,
    }
}

diesel::table! {
    ai_providers (id) {
        id -> Int8,
        user_id -> Int8,
        name -> Varchar,
        configuration -> Jsonb,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
    }
}

diesel::table! {
    event_attendances (id) {
        id -> Int8,
        occasion_id -> Int8,
        user_id -> Nullable<Int8>,
        anonymous_attendee -> Nullable<Jsonb>,
        number_of_guests -> Int4,
        status -> Varchar,
        inviting_user_id -> Nullable<Int8>,
        public_note -> Varchar,
        private_note -> Varchar,
        moderation -> Varchar,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
    }
}

diesel::table! {
    occasion_sync_destinations (occasion_id, sync_destination_id) {
        occasion_id -> Int8,
        sync_destination_id -> Int8,
        destination_instance_id -> Nullable<Varchar>,
        destination_url -> Nullable<Varchar>,
        synced_at -> Nullable<Timestamp>,
        created_at -> Timestamp,
    }
}

diesel::table! {
    use diesel::sql_types::*;
    use diesel_full_text_search::TsVector;

    occasions (post_id) {
        event_id -> Int8,
        post_id -> Int8,
        info -> Jsonb,
        starts_at -> Timestamp,
        ends_at -> Timestamp,
        location -> Nullable<Jsonb>,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
        search_text -> TsVector,
        user_id -> Nullable<Int8>,
        sync_missing_since -> Nullable<Timestamp>,
        timezone -> Nullable<Varchar>,
    }
}

diesel::table! {
    events (post_id) {
        post_id -> Int8,
        info -> Jsonb,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
    }
}

diesel::table! {
    federated_accounts (id) {
        id -> Int8,
        federated_server_id -> Nullable<Int8>,
        federated_user_id -> Varchar,
        user_id -> Nullable<Int8>,
    }
}

diesel::table! {
    federated_profiles (id) {
        id -> Int8,
        user_id -> Int8,
        federated_user_id -> Int8,
        created_at -> Timestamp,
    }
}

diesel::table! {
    federated_servers (id) {
        id -> Int8,
        server_location -> Varchar,
    }
}

diesel::table! {
    federated_users (id) {
        id -> Int8,
        remote_user_id -> Varchar,
        server_host -> Varchar,
        created_at -> Timestamp,
    }
}

diesel::table! {
    follows (id) {
        id -> Int8,
        user_id -> Int8,
        target_user_id -> Int8,
        target_user_moderation -> Varchar,
        created_at -> Timestamp,
        updated_at -> Timestamp,
    }
}

diesel::table! {
    group_posts (id) {
        id -> Int8,
        group_id -> Int8,
        post_id -> Int8,
        user_id -> Int8,
        group_moderation -> Varchar,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
    }
}

diesel::table! {
    groups (id) {
        id -> Int8,
        name -> Varchar,
        shortname -> Varchar,
        description -> Text,
        avatar_media_id -> Nullable<Int8>,
        visibility -> Varchar,
        non_member_permissions -> Jsonb,
        default_membership_permissions -> Jsonb,
        default_membership_moderation -> Varchar,
        default_post_moderation -> Varchar,
        default_event_moderation -> Varchar,
        moderation -> Varchar,
        member_count -> Int4,
        post_count -> Int4,
        event_count -> Int4,
        created_at -> Timestamp,
        updated_at -> Timestamp,
    }
}

diesel::table! {
    market_payments (id) {
        id -> Int8,
        purchase_id -> Int8,
        amount -> Int4,
        currency -> Int4,
        created_at -> Timestamp,
        stripe_payment_intent_id -> Nullable<Varchar>,
        stripe_refund_id -> Nullable<Varchar>,
    }
}

diesel::table! {
    market_products (id) {
        id -> Int8,
        product_type -> Varchar,
        period -> Varchar,
        amount -> Int4,
        currency -> Int4,
        details -> Jsonb,
        created_at -> Timestamp,
        delisted_at -> Nullable<Timestamp>,
    }
}

diesel::table! {
    market_purchases (id) {
        id -> Int8,
        buyer_id -> Int8,
        product_id -> Int8,
        subscription_id -> Nullable<Int8>,
        product_type -> Varchar,
        details -> Jsonb,
        created_at -> Timestamp,
        stripe_checkout_session_id -> Nullable<Varchar>,
        stripe_payment_intent_id -> Nullable<Varchar>,
    }
}

diesel::table! {
    market_subscriptions (id) {
        id -> Int8,
        buyer_id -> Int8,
        product_id -> Int8,
        product_type -> Varchar,
        period -> Varchar,
        amount -> Int4,
        currency -> Int4,
        details -> Jsonb,
        created_at -> Timestamp,
        renews_at -> Nullable<Timestamp>,
        ended_at -> Nullable<Timestamp>,
        stripe_customer_id -> Nullable<Varchar>,
        stripe_payment_method_id -> Nullable<Varchar>,
    }
}

diesel::table! {
    media (id) {
        id -> Int8,
        user_id -> Nullable<Int8>,
        name -> Nullable<Varchar>,
        description -> Nullable<Text>,
        generated -> Bool,
        processed -> Bool,
        visibility -> Varchar,
        moderation -> Varchar,
        created_at -> Timestamp,
        updated_at -> Timestamp,
        metadata -> Jsonb,
        sizes -> Jsonb,
    }
}

diesel::table! {
    memberships (id) {
        id -> Int8,
        user_id -> Int8,
        group_id -> Int8,
        permissions -> Jsonb,
        group_moderation -> Varchar,
        user_moderation -> Varchar,
        created_at -> Timestamp,
        updated_at -> Timestamp,
    }
}

diesel::table! {
    message_reads (message_id, user_id) {
        message_id -> Int8,
        user_id -> Int8,
        read_at -> Timestamp,
    }
}

diesel::table! {
    use diesel::sql_types::*;
    use super::sql_types::RecipientType;

    message_recipients (id) {
        id -> Int8,
        message_id -> Int8,
        user_id -> Int8,
        recipient_type -> RecipientType,
        created_at -> Timestamp,
    }
}

diesel::table! {
    use diesel::sql_types::*;
    use diesel_full_text_search::TsVector;

    messages (id) {
        id -> Int8,
        from_user_id -> Nullable<Int8>,
        subject -> Nullable<Varchar>,
        body_text -> Nullable<Text>,
        email_headers -> Nullable<Jsonb>,
        email_message_id -> Nullable<Varchar>,
        email_minio_path -> Nullable<Varchar>,
        created_at -> Timestamp,
        search_text -> TsVector,
        messaging_group_id -> Int8,
    }
}

diesel::table! {
    messaging_groups (id) {
        id -> Int8,
        sorted_user_ids -> Array<Nullable<Int8>>,
        created_at -> Timestamp,
    }
}

diesel::table! {
    post_sync_destinations (post_id, sync_destination_id) {
        post_id -> Int8,
        sync_destination_id -> Int8,
        destination_instance_id -> Nullable<Varchar>,
        destination_url -> Nullable<Varchar>,
        synced_at -> Nullable<Timestamp>,
        created_at -> Timestamp,
    }
}

diesel::table! {
    use diesel::sql_types::*;
    use diesel_full_text_search::TsVector;
    use super::sql_types::PostMediaLayout;

    posts (id) {
        id -> Int8,
        user_id -> Nullable<Int8>,
        parent_post_id -> Nullable<Int8>,
        title -> Nullable<Varchar>,
        link -> Nullable<Varchar>,
        content -> Nullable<Text>,
        response_count -> Int4,
        reply_count -> Int4,
        group_count -> Int4,
        media -> Array<Nullable<Int8>>,
        media_generated -> Bool,
        embed_link -> Bool,
        shareable -> Bool,
        context -> Varchar,
        visibility -> Varchar,
        moderation -> Varchar,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
        published_at -> Nullable<Timestamp>,
        last_activity_at -> Timestamp,
        unauthenticated_star_count -> Int8,
        search_text -> TsVector,
        sort_published_at -> Timestamp,
        post_media_layout -> PostMediaLayout,
        sync_source_id -> Nullable<Int8>,
        sync_source_uid -> Nullable<Varchar>,
        sync_source_recurrence_anchor -> Nullable<Timestamp>,
    }
}

diesel::table! {
    push_subscriptions (id) {
        id -> Int8,
        user_id -> Int8,
        endpoint -> Varchar,
        p256dh_key -> Varchar,
        auth_key -> Varchar,
        created_at -> Timestamp,
    }
}

diesel::table! {
    server_configurations (id) {
        id -> Int8,
        active -> Bool,
        server_info -> Jsonb,
        anonymous_user_permissions -> Jsonb,
        default_user_permissions -> Jsonb,
        basic_user_permissions -> Jsonb,
        people_settings -> Jsonb,
        group_settings -> Jsonb,
        post_settings -> Jsonb,
        event_settings -> Jsonb,
        external_cdn_config -> Nullable<Jsonb>,
        private_user_strategy -> Varchar,
        authentication_features -> Jsonb,
        created_at -> Timestamp,
        updated_at -> Timestamp,
        federation_info -> Jsonb,
        web_push_config -> Nullable<Jsonb>,
        custom_tabs -> Nullable<Jsonb>,
        cluster_resources -> Nullable<Jsonb>,
        twilio_config -> Nullable<Jsonb>,
        bird_config -> Nullable<Jsonb>,
        preferred_verification_apis -> Nullable<Jsonb>,
        media_settings -> Nullable<Jsonb>,
        stripe_config -> Nullable<Jsonb>,
    }
}

diesel::table! {
    sync_destinations (id) {
        id -> Int8,
        user_id -> Int8,
        configuration -> Jsonb,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
    }
}

diesel::table! {
    sync_sources (id) {
        id -> Int8,
        user_id -> Int8,
        sync_interval_seconds -> Int8,
        configuration -> Jsonb,
        last_synced_at -> Nullable<Timestamp>,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
        event_count -> Int8,
        occasion_count -> Int8,
        post_count -> Int8,
    }
}

diesel::table! {
    user_access_tokens (id) {
        id -> Int8,
        refresh_token_id -> Int8,
        token -> Varchar,
        created_at -> Timestamp,
        expires_at -> Timestamp,
    }
}

diesel::table! {
    user_devices (id) {
        id -> Int8,
        user_id -> Int8,
        device_name -> Varchar,
    }
}

diesel::table! {
    user_posts (id) {
        id -> Int8,
        user_id -> Int8,
        post_id -> Int8,
        created_at -> Timestamp,
        updated_at -> Nullable<Timestamp>,
    }
}

diesel::table! {
    user_refresh_tokens (id) {
        id -> Int8,
        user_id -> Int8,
        token -> Varchar,
        created_at -> Timestamp,
        expires_at -> Nullable<Timestamp>,
        device_name -> Nullable<Varchar>,
        third_party -> Bool,
    }
}

diesel::table! {
    use diesel::sql_types::*;
    use diesel_full_text_search::TsVector;

    users (id) {
        id -> Int8,
        username -> Varchar,
        password_salted_hash -> Varchar,
        real_name -> Varchar,
        email -> Nullable<Jsonb>,
        phone -> Nullable<Jsonb>,
        permissions -> Jsonb,
        avatar_media_id -> Nullable<Int8>,
        bio -> Text,
        visibility -> Varchar,
        moderation -> Varchar,
        default_follow_moderation -> Varchar,
        follower_count -> Int4,
        following_count -> Int4,
        group_count -> Int4,
        post_count -> Int4,
        event_count -> Int4,
        response_count -> Int4,
        created_at -> Timestamp,
        updated_at -> Timestamp,
        search_text -> TsVector,
        friend_count -> Int4,
        occasion_count -> Int4,
        media_storage_limit_bytes -> Nullable<Int8>,
        media_storage_bytes_used -> Int8,
    }
}

diesel::joinable!(ai_provider_grants -> ai_providers (ai_provider_id));
diesel::joinable!(ai_provider_grants -> users (grantee_id));
diesel::joinable!(ai_providers -> users (user_id));
diesel::joinable!(event_attendances -> occasions (occasion_id));
diesel::joinable!(occasion_sync_destinations -> occasions (occasion_id));
diesel::joinable!(occasion_sync_destinations -> sync_destinations (sync_destination_id));
diesel::joinable!(occasions -> events (event_id));
diesel::joinable!(occasions -> posts (post_id));
diesel::joinable!(events -> posts (post_id));
diesel::joinable!(federated_accounts -> federated_servers (federated_server_id));
diesel::joinable!(federated_accounts -> users (user_id));
diesel::joinable!(federated_profiles -> federated_users (federated_user_id));
diesel::joinable!(federated_profiles -> users (user_id));
diesel::joinable!(group_posts -> groups (group_id));
diesel::joinable!(group_posts -> posts (post_id));
diesel::joinable!(group_posts -> users (user_id));
diesel::joinable!(groups -> media (avatar_media_id));
diesel::joinable!(market_payments -> market_purchases (purchase_id));
diesel::joinable!(market_purchases -> market_products (product_id));
diesel::joinable!(market_purchases -> market_subscriptions (subscription_id));
diesel::joinable!(market_purchases -> users (buyer_id));
diesel::joinable!(market_subscriptions -> market_products (product_id));
diesel::joinable!(market_subscriptions -> users (buyer_id));
diesel::joinable!(memberships -> groups (group_id));
diesel::joinable!(memberships -> users (user_id));
diesel::joinable!(message_reads -> messages (message_id));
diesel::joinable!(message_reads -> users (user_id));
diesel::joinable!(message_recipients -> messages (message_id));
diesel::joinable!(message_recipients -> users (user_id));
diesel::joinable!(messages -> messaging_groups (messaging_group_id));
diesel::joinable!(messages -> users (from_user_id));
diesel::joinable!(post_sync_destinations -> posts (post_id));
diesel::joinable!(post_sync_destinations -> sync_destinations (sync_destination_id));
diesel::joinable!(posts -> sync_sources (sync_source_id));
diesel::joinable!(posts -> users (user_id));
diesel::joinable!(push_subscriptions -> users (user_id));
diesel::joinable!(sync_destinations -> users (user_id));
diesel::joinable!(sync_sources -> users (user_id));
diesel::joinable!(user_access_tokens -> user_refresh_tokens (refresh_token_id));
diesel::joinable!(user_devices -> users (user_id));
diesel::joinable!(user_posts -> posts (post_id));
diesel::joinable!(user_posts -> users (user_id));
diesel::joinable!(user_refresh_tokens -> users (user_id));

diesel::allow_tables_to_appear_in_same_query!(
    ai_provider_grants,
    ai_providers,
    event_attendances,
    occasion_sync_destinations,
    occasions,
    events,
    federated_accounts,
    federated_profiles,
    federated_servers,
    federated_users,
    follows,
    group_posts,
    groups,
    market_payments,
    market_products,
    market_purchases,
    market_subscriptions,
    media,
    memberships,
    message_reads,
    message_recipients,
    messages,
    messaging_groups,
    post_sync_destinations,
    posts,
    push_subscriptions,
    server_configurations,
    sync_destinations,
    sync_sources,
    user_access_tokens,
    user_devices,
    user_posts,
    user_refresh_tokens,
    users,
);
