use crate::models;
use crate::protos::*;
use rellm_server::Rellm;
use std::sync::Arc;
use tonic::{Code, Request, Response, Status};

use crate::auth;
use crate::db_connection::*;
use crate::rpcs;

use futures::Stream;
use std::{pin::Pin, time::Duration};
use tokio::sync::mpsc;
use tokio_stream::{wrappers::ReceiverStream, StreamExt};

pub struct RellmService {
    pub pool: Arc<PgPool>,
    pub bucket: Arc<s3::Bucket>,
}

impl Clone for RellmService {
    fn clone(&self) -> Self {
        RellmService {
            pool: self.pool.clone(),
            bucket: self.bucket.clone(),
        }
    }
}

type ReplyStreamResult<T> = Result<Response<T>, Status>;
type ReplyStream = Pin<Box<dyn Stream<Item = Result<Post, Status>> + Send>>;

macro_rules! auth_rpc {
    ($self: expr, $rpc:expr, $request:expr) => {{
        let mut conn = get_connection(&$self.pool)?;
        log::info!(
            "Auth RPC called: {} (request/result hidden)",
            stringify!($rpc)
        );
        $rpc($request.into_inner(), &mut conn).map(Response::new)
    }};
}

macro_rules! authenticated_rpc {
    ($self: expr, $rpc:expr, $request:expr) => {{
        let mut conn = get_connection(&$self.pool)?;
        let user = auth::get_auth_user(&$request, &mut conn)?.ok_or(Status::new(
            Code::Unauthenticated,
            "authentication_required",
        ))?;
        let inner = $request.into_inner();
        let request_log = format!("{:?}", &inner);
        let result = $rpc(inner, &user, &mut conn);
        let truncated_result = format!("{:?}", &result)
            .chars()
            .take(1000)
            .collect::<String>();
        log::info!(
            "Authenticated RPC: {}\tRequest: {:?}\tResult: {:?}",
            stringify!($rpc),
            request_log,
            truncated_result
        );
        result.map(Response::new)
    }};
}

/// Like `authenticated_rpc!`, but for RPCs that also need object storage access (e.g. to clean up
/// objects backing deleted Media) and are therefore `async fn`s themselves.
macro_rules! authenticated_bucket_rpc {
    ($self: expr, $rpc:expr, $request:expr) => {{
        let mut conn = get_connection(&$self.pool)?;
        let user = auth::get_auth_user(&$request, &mut conn)?.ok_or(Status::new(
            Code::Unauthenticated,
            "authentication_required",
        ))?;
        let inner = $request.into_inner();
        let request_log = format!("{:?}", &inner);
        let result = $rpc(inner, &user, &mut conn, &$self.bucket).await;
        let truncated_result = format!("{:?}", &result)
            .chars()
            .take(1000)
            .collect::<String>();
        log::info!(
            "Authenticated RPC: {}\tRequest: {:?}\tResult: {:?}",
            stringify!($rpc),
            request_log,
            truncated_result
        );
        result.map(Response::new)
    }};
}

macro_rules! unauthenticated_rpc {
    ($self: expr, $rpc:expr, $request:expr) => {{
        let mut conn = get_connection(&$self.pool)?;
        let user: Option<models::User> = auth::get_auth_user(&$request, &mut conn)?;
        let inner = $request.into_inner();
        let request_log = format!("{:?}", &inner);
        let result = $rpc(inner, &user.as_ref(), &mut conn);
        let truncated_result = format!("{:?}", &result)
            .chars()
            .take(1000)
            .collect::<String>();
        log::info!(
            "Unauthenticated RPC: {}\tRequest: {:?}\tResult: {:?}",
            stringify!($rpc),
            request_log,
            truncated_result
        );
        result.map(Response::new)
    }};
}

/// For `LockClusterResources`/`FreeClusterResources` -- cluster-internal, server-to-server calls
/// with no per-user auth at all. Authorization is instead the `cluster-shared-secret` gRPC
/// metadata header, checked against the conductor's own stored
/// `ClusterResources.cluster_shared_secret` inside `$rpc` itself (see
/// `lock_cluster_resources::validate_conductor`).
macro_rules! cluster_rpc {
    ($self: expr, $rpc:expr, $request:expr) => {{
        let mut conn = get_connection(&$self.pool)?;
        let shared_secret = $request
            .metadata()
            .get("cluster-shared-secret")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string();
        let inner = $request.into_inner();
        log::info!("Cluster RPC called: {} (request/secret hidden)", stringify!($rpc));
        let result = $rpc(inner, &shared_secret, &mut conn);
        result.map(Response::new)
    }};
}

/// For `FreeClusterResources` only -- like `cluster_rpc!`, but also resolves the normal
/// per-user auth (an `Authorization` header, same as `unauthenticated_rpc!`) alongside the
/// `cluster-shared-secret` one, since `rpcs::free_cluster_resources` accepts either (see that
/// function's own doc): an authenticated admin with `EDIT_CLUSTER_SETTINGS` calling from the
/// `ClusterTab` UI, or a cluster-internal caller presenting the shared secret. A bad/expired
/// bearer token still fails outright here (via `?`), same as every other RPC that reads one --
/// only its *absence* falls through to the shared-secret path.
macro_rules! cluster_rpc_or_authenticated {
    ($self: expr, $rpc:expr, $request:expr) => {{
        let mut conn = get_connection(&$self.pool)?;
        let user: Option<models::User> = auth::get_auth_user(&$request, &mut conn)?;
        let shared_secret = $request
            .metadata()
            .get("cluster-shared-secret")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string();
        let inner = $request.into_inner();
        log::info!(
            "Cluster RPC called: {} (request/secret hidden, authenticated: {})",
            stringify!($rpc),
            user.is_some()
        );
        let result = $rpc(inner, &user.as_ref(), &shared_secret, &mut conn);
        result.map(Response::new)
    }};
}

macro_rules! unauthenticated_unlogged_rpc {
    ($self: expr, $rpc:expr, $request:expr) => {{
        let mut conn = get_connection(&$self.pool)?;
        let user: Option<models::User> = auth::get_auth_user(&$request, &mut conn).ok().flatten();
        let inner = $request.into_inner();
        let result = $rpc(inner, &user.as_ref(), &mut conn);
        result.map(Response::new)
    }};
}

#[tonic::async_trait]
impl Rellm for RellmService {
    async fn get_service_version(
        &self,
        _request: Request<()>,
    ) -> Result<Response<GetServiceVersionResponse>, Status> {
        rpcs::get_service_version().map(Response::new)
    }

    async fn get_server_configuration(
        &self,
        request: Request<()>,
    ) -> Result<Response<ServerConfiguration>, Status> {
        unauthenticated_rpc!(self, rpcs::get_server_configuration, request)
    }

    async fn configure_server(
        &self,
        request: Request<ServerConfiguration>,
    ) -> Result<Response<ServerConfiguration>, Status> {
        authenticated_rpc!(self, rpcs::configure_server, request)
    }

    async fn reset_data(&self, request: Request<()>) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::reset_data, request)
    }

    async fn lock_cluster_resources(
        &self,
        request: Request<LockClusterResourcesRequest>,
    ) -> Result<Response<LockClusterResourcesResponse>, Status> {
        cluster_rpc!(self, rpcs::lock_cluster_resources, request)
    }

    async fn free_cluster_resources(
        &self,
        request: Request<FreeClusterResourcesRequest>,
    ) -> Result<Response<()>, Status> {
        cluster_rpc_or_authenticated!(self, rpcs::free_cluster_resources, request)
    }

    async fn create_account(
        &self,
        request: Request<CreateAccountRequest>,
    ) -> Result<Response<RefreshTokenResponse>, Status> {
        auth_rpc!(self, rpcs::create_account, request)
    }

    async fn login(
        &self,
        request: Request<LoginRequest>,
    ) -> Result<Response<RefreshTokenResponse>, Status> {
        auth_rpc!(self, rpcs::login, request)
    }

    async fn access_token(
        &self,
        request: Request<AccessTokenRequest>,
    ) -> Result<Response<AccessTokenResponse>, Status> {
        auth_rpc!(self, rpcs::access_token, request)
    }

    async fn reset_password(
        &self,
        request: Request<ResetPasswordRequest>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::reset_password, request)
    }

    async fn get_current_user(&self, request: Request<()>) -> Result<Response<User>, Status> {
        authenticated_rpc!(self, rpcs::get_current_user, request)
    }

    async fn update_user(&self, request: Request<User>) -> Result<Response<User>, Status> {
        authenticated_rpc!(self, rpcs::update_user, request)
    }

    async fn start_contact_method_verification(
        &self,
        request: Request<ContactMethod>,
    ) -> Result<Response<ContactMethod>, Status> {
        authenticated_rpc!(self, rpcs::start_contact_method_verification, request)
    }

    async fn verify_contact_method(
        &self,
        request: Request<VerifyContactMethodRequest>,
    ) -> Result<Response<ContactMethod>, Status> {
        authenticated_rpc!(self, rpcs::verify_contact_method, request)
    }

    async fn delete_user(&self, request: Request<User>) -> Result<Response<()>, Status> {
        authenticated_bucket_rpc!(self, rpcs::delete_user, request)
    }
    async fn get_users(
        &self,
        request: Request<GetUsersRequest>,
    ) -> Result<Response<GetUsersResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_users, request)
    }

    async fn send_message(
        &self,
        request: Request<SendMessageRequest>,
    ) -> Result<Response<Message>, Status> {
        // Not `unauthenticated_rpc!` -- `rpcs::send_message` takes an extra `pool` (beyond
        // `unauthenticated_rpc!`'s usual `request`/`user`/`conn`) to spawn
        // `web_push::notify_message_recipients` with its own connection; see that fn's own doc
        // comment on why it can't just reuse this method's `conn`.
        let mut conn = get_connection(&self.pool)?;
        let user: Option<models::User> = auth::get_auth_user(&request, &mut conn)?;
        let inner = request.into_inner();
        let result = rpcs::send_message(inner, &user.as_ref(), &mut conn, self.pool.clone());
        result.map(Response::new)
    }
    async fn get_messages(
        &self,
        request: Request<GetMessagesRequest>,
    ) -> Result<Response<GetMessagesResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_messages, request)
    }
    async fn mark_messages_read(
        &self,
        request: Request<MarkMessagesReadRequest>,
    ) -> Result<Response<MarkMessagesReadResponse>, Status> {
        authenticated_rpc!(self, rpcs::mark_messages_read, request)
    }

    async fn register_push_subscription(
        &self,
        request: Request<RegisterPushSubscriptionRequest>,
    ) -> Result<Response<PushSubscription>, Status> {
        authenticated_rpc!(self, rpcs::register_push_subscription, request)
    }
    async fn unregister_push_subscription(
        &self,
        request: Request<UnregisterPushSubscriptionRequest>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::unregister_push_subscription, request)
    }
    async fn get_push_subscription_status(
        &self,
        request: Request<GetPushSubscriptionStatusRequest>,
    ) -> Result<Response<GetPushSubscriptionStatusResponse>, Status> {
        authenticated_rpc!(self, rpcs::get_push_subscription_status, request)
    }

    async fn create_follow(&self, request: Request<Follow>) -> Result<Response<Follow>, Status> {
        authenticated_rpc!(self, rpcs::create_follow, request)
    }
    async fn update_follow(&self, request: Request<Follow>) -> Result<Response<Follow>, Status> {
        authenticated_rpc!(self, rpcs::update_follow, request)
    }
    async fn delete_follow(&self, request: Request<Follow>) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_follow, request)
    }

    async fn get_media(
        &self,
        request: Request<GetMediaRequest>,
    ) -> Result<Response<GetMediaResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_media, request)
    }

    async fn delete_media(&self, request: Request<Media>) -> Result<Response<()>, Status> {
        authenticated_bucket_rpc!(self, rpcs::delete_media, request)
    }

    async fn update_media(&self, request: Request<Media>) -> Result<Response<Media>, Status> {
        authenticated_bucket_rpc!(self, rpcs::update_media, request)
    }

    async fn delete_media_sizes(
        &self,
        request: Request<Media>,
    ) -> Result<Response<Media>, Status> {
        authenticated_bucket_rpc!(self, rpcs::delete_media_sizes, request)
    }

    async fn get_groups(
        &self,
        request: Request<GetGroupsRequest>,
    ) -> Result<Response<GetGroupsResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_groups, request)
    }

    async fn create_group(&self, request: Request<Group>) -> Result<Response<Group>, Status> {
        authenticated_rpc!(self, rpcs::create_group, request)
    }

    async fn update_group(&self, request: Request<Group>) -> Result<Response<Group>, Status> {
        authenticated_rpc!(self, rpcs::update_group, request)
    }
    async fn delete_group(&self, request: Request<Group>) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_group, request)
    }

    async fn create_membership(
        &self,
        request: Request<Membership>,
    ) -> Result<Response<Membership>, Status> {
        authenticated_rpc!(self, rpcs::create_membership, request)
    }
    async fn update_membership(
        &self,
        request: Request<Membership>,
    ) -> Result<Response<Membership>, Status> {
        authenticated_rpc!(self, rpcs::update_membership, request)
    }
    async fn delete_membership(
        &self,
        request: Request<Membership>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_membership, request)
    }
    async fn get_members(
        &self,
        request: Request<GetMembersRequest>,
    ) -> Result<Response<GetMembersResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_members, request)
    }

    async fn create_post(&self, request: Request<Post>) -> Result<Response<Post>, Status> {
        authenticated_rpc!(self, rpcs::create_post, request)
    }
    async fn update_post(&self, request: Request<Post>) -> Result<Response<Post>, Status> {
        authenticated_rpc!(self, rpcs::update_post, request)
    }
    async fn delete_post(&self, request: Request<Post>) -> Result<Response<Post>, Status> {
        authenticated_rpc!(self, rpcs::delete_post, request)
    }

    async fn sync_post(&self, request: Request<SyncPostRequest>) -> Result<Response<Post>, Status> {
        authenticated_rpc!(self, rpcs::sync_post, request)
    }
    async fn delete_post_sync_destination(
        &self,
        request: Request<DeletePostSyncDestinationRequest>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_post_sync_destination, request)
    }

    async fn star_post(&self, request: Request<Post>) -> Result<Response<Post>, Status> {
        unauthenticated_unlogged_rpc!(self, rpcs::star_post, request)
    }

    async fn unstar_post(&self, request: Request<Post>) -> Result<Response<Post>, Status> {
        unauthenticated_unlogged_rpc!(self, rpcs::unstar_post, request)
    }

    async fn create_group_post(
        &self,
        request: Request<GroupPost>,
    ) -> Result<Response<GroupPost>, Status> {
        authenticated_rpc!(self, rpcs::create_group_post, request)
    }
    async fn update_group_post(
        &self,
        request: Request<GroupPost>,
    ) -> Result<Response<GroupPost>, Status> {
        authenticated_rpc!(self, rpcs::update_group_post, request)
    }
    async fn delete_group_post(&self, request: Request<GroupPost>) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_group_post, request)
    }

    async fn get_group_posts(
        &self,
        request: Request<GetGroupPostsRequest>,
    ) -> Result<Response<GetGroupPostsResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_group_posts, request)
    }

    async fn get_posts(
        &self,
        request: Request<GetPostsRequest>,
    ) -> Result<Response<GetPostsResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_posts, request)
    }

    async fn create_event(&self, request: Request<Event>) -> Result<Response<Event>, Status> {
        authenticated_rpc!(self, rpcs::create_event, request)
    }
    async fn update_event(&self, request: Request<Event>) -> Result<Response<Event>, Status> {
        authenticated_rpc!(self, rpcs::update_event, request)
    }
    async fn delete_event(&self, request: Request<Event>) -> Result<Response<Event>, Status> {
        authenticated_rpc!(self, rpcs::delete_event, request)
    }
    async fn update_event_details(
        &self,
        request: Request<Event>,
    ) -> Result<Response<Event>, Status> {
        authenticated_rpc!(self, rpcs::update_event_details, request)
    }
    async fn create_new_occasions(
        &self,
        request: Request<Event>,
    ) -> Result<Response<Event>, Status> {
        authenticated_rpc!(self, rpcs::create_new_occasions, request)
    }
    async fn update_occasions(
        &self,
        request: Request<Event>,
    ) -> Result<Response<Event>, Status> {
        authenticated_rpc!(self, rpcs::update_occasions, request)
    }
    async fn delete_removed_occasions(
        &self,
        request: Request<Event>,
    ) -> Result<Response<Event>, Status> {
        authenticated_rpc!(self, rpcs::delete_removed_occasions, request)
    }
    async fn get_events(
        &self,
        request: Request<GetEventsRequest>,
    ) -> Result<Response<GetEventsResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_events, request)
    }

    async fn get_sync_sources(
        &self,
        request: Request<User>,
    ) -> Result<Response<GetSyncSourcesResponse>, Status> {
        authenticated_rpc!(self, rpcs::get_sync_sources, request)
    }
    async fn create_sync_source(
        &self,
        request: Request<SyncSource>,
    ) -> Result<Response<SyncSource>, Status> {
        authenticated_rpc!(self, rpcs::create_sync_source, request)
    }
    async fn update_sync_source(
        &self,
        request: Request<SyncSource>,
    ) -> Result<Response<SyncSource>, Status> {
        authenticated_rpc!(self, rpcs::update_sync_source, request)
    }
    async fn delete_sync_source(
        &self,
        request: Request<DeleteSyncSourceRequest>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_sync_source, request)
    }

    async fn get_sync_destinations(
        &self,
        request: Request<User>,
    ) -> Result<Response<GetSyncDestinationsResponse>, Status> {
        authenticated_rpc!(self, rpcs::get_sync_destinations, request)
    }
    async fn create_sync_destination(
        &self,
        request: Request<SyncDestination>,
    ) -> Result<Response<SyncDestination>, Status> {
        authenticated_rpc!(self, rpcs::create_sync_destination, request)
    }
    async fn update_sync_destination(
        &self,
        request: Request<SyncDestination>,
    ) -> Result<Response<SyncDestination>, Status> {
        authenticated_rpc!(self, rpcs::update_sync_destination, request)
    }
    async fn delete_sync_destination(
        &self,
        request: Request<DeleteSyncDestinationRequest>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_sync_destination, request)
    }
    async fn sync_occasion(
        &self,
        request: Request<SyncOccasionRequest>,
    ) -> Result<Response<Occasion>, Status> {
        authenticated_rpc!(self, rpcs::sync_occasion, request)
    }
    async fn delete_occasion_sync_destination(
        &self,
        request: Request<DeleteOccasionSyncDestinationRequest>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_occasion_sync_destination, request)
    }

    async fn get_ai_providers(
        &self,
        request: Request<User>,
    ) -> Result<Response<GetAiProvidersResponse>, Status> {
        authenticated_rpc!(self, rpcs::get_ai_providers, request)
    }
    async fn create_ai_provider(
        &self,
        request: Request<AiProvider>,
    ) -> Result<Response<AiProvider>, Status> {
        authenticated_rpc!(self, rpcs::create_ai_provider, request)
    }
    async fn update_ai_provider(
        &self,
        request: Request<AiProvider>,
    ) -> Result<Response<AiProvider>, Status> {
        authenticated_rpc!(self, rpcs::update_ai_provider, request)
    }
    async fn delete_ai_provider(
        &self,
        request: Request<DeleteAiProviderRequest>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::delete_ai_provider, request)
    }
    async fn grant_ai_provider(
        &self,
        request: Request<GrantAiProviderRequest>,
    ) -> Result<Response<AiProviderGrant>, Status> {
        authenticated_rpc!(self, rpcs::grant_ai_provider, request)
    }
    async fn revoke_ai_provider(
        &self,
        request: Request<RevokeAiProviderRequest>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::revoke_ai_provider, request)
    }
    async fn generate_media(
        &self,
        request: Request<GenerateMediaRequest>,
    ) -> Result<Response<Media>, Status> {
        authenticated_bucket_rpc!(self, rpcs::generate_media, request)
    }

    async fn get_market_products(
        &self,
        request: Request<GetMarketProductsRequest>,
    ) -> Result<Response<GetMarketProductsResponse>, Status> {
        unauthenticated_rpc!(self, rpcs::get_market_products, request)
    }
    async fn create_market_product(
        &self,
        request: Request<MarketProduct>,
    ) -> Result<Response<MarketProduct>, Status> {
        authenticated_rpc!(self, rpcs::create_market_product, request)
    }
    async fn update_market_product(
        &self,
        request: Request<MarketProduct>,
    ) -> Result<Response<MarketProduct>, Status> {
        authenticated_rpc!(self, rpcs::update_market_product, request)
    }
    async fn get_market_subscriptions(
        &self,
        request: Request<GetMarketSubscriptionsRequest>,
    ) -> Result<Response<GetMarketSubscriptionsResponse>, Status> {
        authenticated_rpc!(self, rpcs::get_market_subscriptions, request)
    }
    async fn cancel_market_subscription(
        &self,
        request: Request<MarketSubscription>,
    ) -> Result<Response<MarketSubscription>, Status> {
        authenticated_rpc!(self, rpcs::cancel_market_subscription, request)
    }
    async fn update_market_subscription(
        &self,
        request: Request<MarketSubscription>,
    ) -> Result<Response<MarketSubscription>, Status> {
        authenticated_rpc!(self, rpcs::update_market_subscription, request)
    }
    async fn make_market_purchase(
        &self,
        request: Request<MakeMarketPurchaseRequest>,
    ) -> Result<Response<MakeMarketPurchaseResponse>, Status> {
        authenticated_rpc!(self, rpcs::make_market_purchase, request)
    }

    async fn upsert_event_attendance(
        &self,
        request: Request<EventAttendance>,
    ) -> Result<Response<EventAttendance>, Status> {
        unauthenticated_rpc!(self, rpcs::upsert_event_attendance, request)
    }
    async fn delete_event_attendance(
        &self,
        request: Request<EventAttendance>,
    ) -> Result<Response<()>, Status> {
        unauthenticated_rpc!(self, rpcs::delete_event_attendance, request)
    }
    async fn get_event_attendances(
        &self,
        request: Request<GetEventAttendancesRequest>,
    ) -> Result<Response<EventAttendances>, Status> {
        unauthenticated_rpc!(self, rpcs::get_event_attendances, request)
    }

    async fn federate_profile(
        &self,
        request: Request<FederatedAccount>,
    ) -> Result<Response<FederatedAccount>, Status> {
        authenticated_rpc!(self, rpcs::federate_profile, request)
    }
    async fn defederate_profile(
        &self,
        request: Request<FederatedAccount>,
    ) -> Result<Response<()>, Status> {
        authenticated_rpc!(self, rpcs::defederate_profile, request)
    }

    type StreamRepliesStream = ReplyStream;
    async fn stream_replies(
        &self,
        req: Request<Post>,
    ) -> ReplyStreamResult<Self::StreamRepliesStream> {
        println!("Rellm::stream_replies");
        println!("\tclient connected from: {:?}", req.remote_addr());

        // creating infinite stream with requested message
        let repeat = std::iter::repeat(Post {
            content: Some("Hello World!".to_string()),
            ..Default::default()
        });
        let mut stream = Box::pin(tokio_stream::iter(repeat).throttle(Duration::from_millis(200)));

        // spawn and channel are required if you want handle "disconnect" functionality
        // the `out_stream` will not be polled after client disconnect
        let (tx, rx) = mpsc::channel(128);
        tokio::spawn(async move {
            while let Some(item) = stream.next().await {
                match tx.send(Result::<_, Status>::Ok(item)).await {
                    Ok(_) => {
                        // item (server response) was queued to be send to client
                    }
                    Err(_item) => {
                        // output_stream was build from rx and both are dropped
                        break;
                    }
                }
            }
            println!("\tclient disconnected");
        });

        let output_stream = ReceiverStream::new(rx);
        Ok(Response::new(
            Box::pin(output_stream) as Self::StreamRepliesStream
        ))
    }
}

fn get_connection(pool: &PgPool) -> Result<PgPooledConnection, Status> {
    match pool.get() {
        Err(_) => Err(Status::new(Code::DataLoss, "database_connection_failure")),
        Ok(conn) => Ok(conn),
    }
}
