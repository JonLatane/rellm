module Components.Users.Username exposing (isReserved, validate)

{-| Client-side mirror of `backend/src/rpcs/validations/validate_fields.rs`'s `validate_username`,
shared by everything that lets someone pick a *new* username (`Components.Pages.UserProfilePage`'s
"Edit Username", `Shared.AccountsPanel`'s Create Account) so they can't drift apart. A leaf module
(no `Shared`/`Components.Users` imports) since `Shared.AccountsPanel` can't import `Components.Users`
without a cycle. Not applied to Log In -- existing accounts may predate a rule.

The backend stays the source of truth (these checks only save a round trip); where Elm can't
express its rule exactly, this errs permissive: `\w` is Unicode-aware in Rust, so any non-ASCII
character is let through rather than guessed at.

-}

import Set exposing (Set)


{-| `Nothing` if `username` (already trimmed) is acceptable, else a user-facing reason.
-}
validate : String -> Maybe String
validate username =
    if String.isEmpty username then
        Just "Username can't be empty."

    else if utf8Length username > 47 then
        Just "Username is too long (max 47 characters)."

    else if not (String.all isWordChar username) then
        Just "Usernames may only contain letters, numbers, \"_\", \".\" and \"-\"."

    else if startsWithReservedCharacter username then
        Just "Usernames can't start with \".\", \"-\" or \"_\"."

    else if Set.member username backendReservedValues || isReserved username then
        Just "That username is reserved."

    else
        Nothing


{-| Usernames that can't be routed to via `/:username[@host]` since they'd collide with this app's
own top-level routes (`Pages.About`, `Pages.People`, elm-spa's builtin `not-found`) or the
`/user`/`/post` prefixes themselves -- e.g. a user named "about" is only ever reachable via
`/user/:id[@host]`. Compared case-insensitively, since the collision is with the URL segment, not
the display name.
-}
isReserved : String -> Bool
isReserved username =
    Set.member (String.toLower (String.trim username)) routingReserved


routingReserved : Set String
routingReserved =
    Set.fromList [ "about", "not-found", "user", "post", "people" ]


isWordChar : Char -> Bool
isWordChar c =
    Char.toCode c > 127 || Char.isAlphaNum c || c == '_' || c == '.' || c == '-'


{-| `RESERVED_LEAD_CHAR_RE` (`^[-._~:/?\[\]@!$&'()*+,;%=]`) intersected with what `isWordChar` lets
through, i.e. `-`, `.` and `_`.
-}
startsWithReservedCharacter : String -> Bool
startsWithReservedCharacter username =
    String.startsWith "-" username || String.startsWith "." username || String.startsWith "_" username


{-| Rust's `str::len` is bytes, not characters -- which is what the backend's 47 limit counts.
-}
utf8Length : String -> Int
utf8Length =
    String.foldl
        (\c total ->
            let
                code : Int
                code =
                    Char.toCode c
            in
            total
                + (if code < 0x80 then
                    1

                   else if code < 0x0800 then
                    2

                   else if code < 0x00010000 then
                    3

                   else
                    4
                  )
        )
        0


{-| `RESERVED_PATHS` from the backend, exact-match (case-sensitive, like the backend).
-}
backendReservedValues : Set String
backendReservedValues =
    Set.fromList
        [ "app", "flutter", "tamagui", "elm", "elm_debug", "debug", "home", "web"
        , "events", "event", "e", "posts", "post", "p", "groups", "group", "g"
        , "people", "person", "author", "a", "member", "m", "server", "s", "servers"
        , "about", "about_rellm", "u", "users", "user", "info", "info_shield"
        , "robots.txt", "favicon.ico", "favicon.png", "sitemap.xml", "sitemap.xml.gz"
        , "media", "video", "videos", "audio", "images", "backend_host", "frontend_host"
        , "docs", "documentation", "event_ai", "third_party_auth", "third_party_auths"
        , "auth", "auths", "oauth", "calendar.ics", "rss.xml", "atom.xml", "contact_integrations"
        ]
