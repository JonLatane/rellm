-- A user's own domain to serve their Rellm Subdomain from (`SubdomainSettings.custom_frontend_host`), e.g. `usersite.com`
-- for `jon.bullcity.social`. Lower case, validated by `logic::subdomains::validate_custom_frontend_host`. A table of its own
-- rather than a `users` column: `users` is at Diesel's 32-column limit. The primary key makes a domain belong to one user
-- (and `resolve_subdomain`'s lookup of a request's host a primary-key probe); `user_id` is unique, one domain per user.
CREATE TABLE subdomain_frontend_hosts (
    host VARCHAR PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
