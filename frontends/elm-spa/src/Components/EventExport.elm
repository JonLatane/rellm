module Components.EventExport exposing (Config, view)

{-| The per-`Occasion` "Add to Calendar" export button -- a circular `⤓` button with a popdown
(`ui/popover.css`, opening down and to the left of the button), the same pieces
`Components.Pages.EventsPage.exportButtonView` builds its own listing-wide iCal export from. Used by
both `Components.Pages.EventPage`'s detail view and (`small`) `Components.Events.eventCard`'s cards.

Offers:

  - **iCal, this date** -- the backend's `GET /calendar.ics?post_id=<occasion post id>` (see
    `backend/src/web/ical_subscription.rs`), exactly one `VEVENT`.
  - **iCal, all dates** -- the same with the _Event's_ post id, i.e. every one of its occasions;
    only offered when more than one occasion is still upcoming, or the caller has seen other dates.
  - **Google Calendar** -- Google's "create event" form prefilled for just this one occasion, in a
    new tab. Built entirely here; no backend involved.

An anonymous attendee's private-RSVP token(s) (`anonymousAuthTokens`, the page's raw
`?anonymousAuthToken=` value) ride along on the iCal links as `anonymous_auth_token` -- passed
straight through to `GetEvents`, so a location hidden until RSVP approval is revealed to them and
the event description gets a "manage your RSVP" link -- and onto the Google Calendar description.

-}

import Components.Events as Events
import Components.Posts as Posts
import Components.Rsvps as Rsvps
import Html exposing (Html, a, button, div, h3, text)
import Html.Attributes exposing (class, href, rel, target, title, type_)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (Event, Occasion)
import Time
import Url
import Url.Builder
import UI.Classes exposing (classes, hostnameToCSSClass, openClosedClass)


type alias Config msg =
    { toggle : msg
    , close : msg
    , isOpen : Bool

    -- The compact button for `eventCard`.
    , small : Bool

    -- The `Event`'s own server (`https://<host>/calendar.ics`, `/event/<id>`).
    , serverHost : String
    , anonymousAuthTokens : Maybe String
    , now : Time.Posix

    -- Whether the caller has seen other dates of this Event beyond `event.occasions` (listings only
    -- carry the occasions in their window), which makes "All dates" worth offering.
    , otherDatesSeen : Bool
    , event : Event
    , occasion : Occasion
    }


view : Config msg -> Html msg
view cfg =
    let
        occasionId : String
        occasionId =
            Rsvps.occasionIdOf cfg.occasion

        upcomingCount : Int
        upcomingCount =
            cfg.event.occasions
                |> List.filter (isUpcoming cfg.now)
                |> List.length

        multipleDates : Bool
        multipleDates =
            cfg.otherDatesSeen || upcomingCount > 1

        icsLink : String -> String
        icsLink postId =
            "https://"
                ++ cfg.serverHost
                ++ "/calendar.ics"
                ++ Url.Builder.toQuery
                    (Url.Builder.string "post_id" postId
                        :: (cfg.anonymousAuthTokens
                                |> Maybe.map (\tokens -> [ Url.Builder.string "anonymous_auth_token" tokens ])
                                |> Maybe.withDefault []
                           )
                    )

        optionLink : String -> String -> Bool -> Html msg
        optionLink label url newTab =
            a
                ([ href url, classes [ "event-export-option", hostnameToCSSClass cfg.serverHost ] ]
                    ++ (if newTab then
                            [ target "_blank", rel "noopener noreferrer" ]

                        else
                            []
                       )
                )
                [ text label ]
    in
    div [ classes [ "event-export", "popover-anchor", if cfg.small then "event-export-small" else "event-export-large" ] ]
        [ button
            [ classes
                [ "filter-icon-button"
                , "popover-toggle"
                , "background-color-nav"
                , "event-export-toggle"
                , openClosedClass cfg.isOpen
                ]
            , onClick cfg.toggle
            , title "Add to calendar"
            , type_ "button"
            ]
            [ text "⤓" ]
        , div [ classes [ "popover-backdrop", openClosedClass cfg.isOpen ], onClick cfg.close ] []
        , div [ classes [ "event-export-popover", "popover", openClosedClass cfg.isOpen ] ]
            [ h3 [ class "event-export-popover-heading" ] [ text "Add to Calendar" ]
            , optionLink
                (if multipleDates then
                    "This date (iCal)"

                 else
                    "iCal (.ics)"
                )
                (icsLink occasionId)
                False
            , case cfg.event.post of
                Just eventPost ->
                    if multipleDates then
                        optionLink "All dates (iCal)" (icsLink eventPost.id) False

                    else
                        text ""

                Nothing ->
                    text ""
            , optionLink "Google Calendar" (googleCalendarUrl cfg) True
            ]
        ]


isUpcoming : Time.Posix -> Occasion -> Bool
isUpcoming now occasion =
    Events.occasionEndsOrStartsAt occasion
        |> Maybe.map (\at -> Time.posixToMillis at >= Time.posixToMillis now)
        |> Maybe.withDefault False


{-| Google's prefilled "create event" form for `cfg.occasion` -- the description carries the
event's own text, a link back to this page, and (when `anonymousAuthTokens` holds this
occasion's token and the Event takes anonymous RSVPs) a link to manage the RSVP.
-}
googleCalendarUrl : Config msg -> String
googleCalendarUrl cfg =
    let
        occasionId : String
        occasionId =
            Rsvps.occasionIdOf cfg.occasion

        eventUrl : String
        eventUrl =
            "https://" ++ cfg.serverHost ++ "/event/" ++ occasionId

        rsvpToken : Maybe String
        rsvpToken =
            if Tuple.second (Rsvps.rsvpsAllowed cfg.event cfg.occasion) then
                cfg.anonymousAuthTokens |> Maybe.andThen (Rsvps.parseAnonymousAuthToken occasionId)

            else
                Nothing

        content : String
        content =
            cfg.event.post |> Maybe.andThen .content |> Maybe.withDefault "" |> String.left 1500

        description : String
        description =
            case rsvpToken of
                Just token ->
                    content ++ "\n\nmanage your RSVP at:\n" ++ eventUrl ++ "?anonymousAuthToken=" ++ Url.percentEncode token

                Nothing ->
                    content ++ "\n\nvia: " ++ eventUrl

        start : Maybe Time.Posix
        start =
            Events.occasionStartsOrEndsAt cfg.occasion

        end : Maybe Time.Posix
        end =
            Events.occasionEndsOrStartsAt cfg.occasion

        dates : List Url.Builder.QueryParameter
        dates =
            case ( start, end ) of
                ( Just s, Just e ) ->
                    [ Url.Builder.string "dates" (utcStamp s ++ "/" ++ utcStamp e) ]

                _ ->
                    []
    in
    "https://calendar.google.com/calendar/render"
        ++ Url.Builder.toQuery
            ([ Url.Builder.string "action" "TEMPLATE"
             , Url.Builder.string "text" (cfg.event.post |> Maybe.map Posts.postTitleText |> Maybe.withDefault "Event")
             , Url.Builder.string "details" description
             ]
                ++ dates
                ++ (cfg.occasion.location
                        |> Maybe.andThen Events.locationText
                        |> Maybe.map (\location -> [ Url.Builder.string "location" location ])
                        |> Maybe.withDefault []
                   )
            )


{-| `20261025T210000Z` -- the UTC form Google Calendar's `dates` parameter takes.
-}
utcStamp : Time.Posix -> String
utcStamp posix =
    let
        pad : Int -> Int -> String
        pad width n =
            String.padLeft width '0' (String.fromInt n)

        month : Int
        month =
            case Time.toMonth Time.utc posix of
                Time.Jan ->
                    1

                Time.Feb ->
                    2

                Time.Mar ->
                    3

                Time.Apr ->
                    4

                Time.May ->
                    5

                Time.Jun ->
                    6

                Time.Jul ->
                    7

                Time.Aug ->
                    8

                Time.Sep ->
                    9

                Time.Oct ->
                    10

                Time.Nov ->
                    11

                Time.Dec ->
                    12
    in
    pad 4 (Time.toYear Time.utc posix)
        ++ pad 2 month
        ++ pad 2 (Time.toDay Time.utc posix)
        ++ "T"
        ++ pad 2 (Time.toHour Time.utc posix)
        ++ pad 2 (Time.toMinute Time.utc posix)
        ++ pad 2 (Time.toSecond Time.utc posix)
        ++ "Z"
