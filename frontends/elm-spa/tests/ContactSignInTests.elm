module ContactSignInTests exposing (suite)

{-| Tests for `Components.ContactSignIn`'s rule: a sign-in contact method of an account with no
password can't be turned off, edited or deleted.
-}

import Components.ContactSignIn as ContactSignIn
import Expect
import Proto.Rellm exposing (ContactMethod, defaultContactMethod)
import Shared.Conversions exposing (posixToTimestamp)
import Test exposing (Test, describe, test)
import Time


contact : Maybe Bool -> ContactMethod
contact useForSignIn =
    { defaultContactMethod
        | value = Just "tel:+19195551234"
        , verifiedAt = Just (posixToTimestamp (Time.millisToPosix 0))
        , useForSignIn = useForSignIn
    }


suite : Test
suite =
    describe "ContactSignIn"
        [ test "only an explicit Just True is a sign-in method" <|
            \_ ->
                Expect.equal [ True, False, False ]
                    [ ContactSignIn.isSignIn (contact (Just True))
                    , ContactSignIn.isSignIn (contact (Just False))
                    , ContactSignIn.isSignIn (contact Nothing)
                    ]
        , test "a sign-in contact method is locked exactly when the account has no password" <|
            \_ ->
                Expect.equal [ True, False ]
                    [ ContactSignIn.locked False (Just (contact (Just True)))
                    , ContactSignIn.locked True (Just (contact (Just True)))
                    ]
        , test "a contact method that isn't a sign-in method is never locked, nor is a missing one" <|
            \_ ->
                Expect.equal [ False, False, False ]
                    [ ContactSignIn.locked False (Just (contact (Just False)))
                    , ContactSignIn.locked False (Just (contact Nothing))
                    , ContactSignIn.locked False Nothing
                    ]
        ]
