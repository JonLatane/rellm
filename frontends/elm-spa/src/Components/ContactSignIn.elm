module Components.ContactSignIn exposing (isSignIn, locked, view)

{-| The "Use for signing in" checkbox under a Phone/Email `ContactMethod` (the Accounts Panel's
Contact Methods item and the profile page's), and the rule that goes with it: while a contact method
is a sign-in method and the account has no password (`User.hasPassword`), it can't be turned off,
edited or deleted -- the server refuses (`password_required_for_sign_in`), and these helpers make the
UI say so up front instead of failing after the fact. Pure: callers pass their own message.
-}

import Html exposing (Html, div, input, label, p, text)
import Html.Attributes exposing (checked, class, disabled, type_)
import Html.Events exposing (onClick)
import Proto.Rellm exposing (ContactMethod)


{-| Whether `contactMethod` is currently one of the account's sign-in methods.
-}
isSignIn : ContactMethod -> Bool
isSignIn contactMethod =
    contactMethod.useForSignIn == Just True


{-| Whether this contact method is the account's way in and there's no password to fall back on --
so its sign-in checkbox, Edit and Delete are all disabled.
-}
locked : Bool -> Maybe ContactMethod -> Bool
locked hasPassword maybeContactMethod =
    not hasPassword && (maybeContactMethod |> Maybe.map isSignIn |> Maybe.withDefault False)


{-| The checkbox (only for a *verified* contact method -- an unverified one just says to verify it
first), plus, while it's locked, why. `methodLabel` is "phone number"/"email address"; `busy`
disables it while a save is in flight; `toggleMsg` flips it.
-}
view : { hasPassword : Bool, methodLabel : String, busy : Bool, toggleMsg : msg } -> Maybe ContactMethod -> Html msg
view config maybeContactMethod =
    case maybeContactMethod of
        Nothing ->
            text ""

        Just contactMethod ->
            if contactMethod.verifiedAt == Nothing then
                p [ class "profile-contact-method-signin-hint" ]
                    [ text ("Verify this " ++ config.methodLabel ++ " to be able to use it for signing in.") ]

            else
                div [ class "profile-contact-method-signin" ]
                    [ label [ class "profile-contact-method-consent-label" ]
                        [ input
                            [ type_ "checkbox"
                            , checked (isSignIn contactMethod)
                            , disabled (config.busy || locked config.hasPassword maybeContactMethod)
                            , onClick config.toggleMsg
                            ]
                            []
                        , text (" Use this " ++ config.methodLabel ++ " for signing in (we'll send you a code).")
                        ]
                    , if locked config.hasPassword maybeContactMethod then
                        p [ class "profile-contact-method-signin-hint" ]
                            [ text
                                ("This is how you sign in, and your account has no password. Set a password before you turn this off, change this "
                                    ++ config.methodLabel
                                    ++ " or delete it -- otherwise you'd be locked out."
                                )
                            ]

                      else
                        text ""
                    ]
