import { FederatedEvent, IdentifiedOccasion, RootState, accountOrServerId, federateId, getCredentialClient, loadRsvpData, useServerTheme } from "app/store";
import React, { useEffect, useState } from "react";

import { RsvpStatus, Rsvp, Permission } from "@rellm/api";
import { Anchor, AnimatePresence, Button, Dialog, Heading, Input, Label, Paragraph, RadioGroup, Select, SizeTokens, Spinner, Text, TextArea, Tooltip, XStack, YStack, ZStack, useDebounceValue, useMedia, useToastController } from "@rellm/ui";
import { createSelector } from "@reduxjs/toolkit";
import { AlertCircle, AlertTriangle, Check, CheckCircle, ChevronDown, ChevronRight, Edit3 as Edit, Plus, ShieldAlert } from "@tamagui/lucide-icons";
import { useGroupContext } from "app/contexts/group_context";
import { useAnonymousAuthToken, useComponentKey, useCurrentServer, useFederatedDispatch, useLocalConfiguration } from "app/hooks";
import { passes, pending, rejected } from "app/utils/moderation_utils";
import { hasPermission } from "app/utils/permission_utils";
import { isPastOccasion } from "app/utils/time";
import { useSelector } from 'react-redux';
import { createParam } from "solito";
import { useLink } from "solito/link";
import { EventCalendarExporter } from "./event_calendar_exporter";
import RsvpCard, { rsvpModerationDescription } from "./rsvp_card";
import { AutoAnimatedList } from "../post";
import { on } from '../../hooks/use_hash';

export interface EventRsvpManagerProps {
  event: FederatedEvent;
  occasion: IdentifiedOccasion;
  newRsvpMode?: RsvpMode;
  setNewRsvpMode?: (mode: RsvpMode) => void;
  isPreview?: boolean;
  isModalPreview?: boolean;
  isVisible?: boolean;
}

export type RsvpMode = 'anonymous' | 'user' | undefined;

const { useParam: useSectionParam } = createParam<{ section: string }>()

export const selectRsvpData = (occasionId: string) =>
  createSelector(
    (state: RootState) => state.events.rsvpData[occasionId],
    (rsvpData) => rsvpData
  );
export const EventRsvpManager: React.FC<EventRsvpManagerProps> = ({
  event,
  occasion,
  newRsvpMode: givenNewRsvpMode,
  setNewRsvpMode: givenSetNewRsvpMode,
  isPreview,
  isModalPreview,
  isVisible,
}) => {
  const mediaQuery = useMedia();
  const { dispatch, accountOrServer } = useFederatedDispatch(event);
  const currentServer = useCurrentServer();
  const { account, server } = accountOrServer;
  const isPrimaryServer = !!currentServer &&
    currentServer?.host === accountOrServer.server?.host;
  const { primaryColor, primaryTextColor, primaryAnchorColor, navColor, navTextColor, navAnchorColor } = useServerTheme(server);

  const isEventOwner = account && account?.user?.id === event?.post?.author?.userId;

  const { anonymousAuthToken, setAnonymousAuthToken, removeAnonymousAuthToken } = useAnonymousAuthToken(occasion.id);
  const [querySection, setQuerySection] = useSectionParam('section');

  const [selfNewRsvpMode, setSelfNewRsvpMode] = useState(undefined as RsvpMode);
  const [newRsvpMode, setNewRsvpMode] = [
    givenNewRsvpMode ?? selfNewRsvpMode,
    givenSetNewRsvpMode ?? setSelfNewRsvpMode
  ];

  const canRsvpNonAnonymously = hasPermission(accountOrServer?.account?.user, Permission.RSVP_TO_EVENTS);
  const canRsvpAnonymously = event?.info?.allowsAnonymousRsvps;
  const showRsvpSection = event?.info?.allowsRsvps;// &&
  //(canRsvpAnonymously || canRsvpNonAnonymously);

  // const [newRsvpMode, setNewRsvpMode] = useState(undefined as RsvpMode);
  const [rsvps, setRsvps] = useState([] as Rsvp[]);
  const currentRsvp = rsvps.find(
    a => account !== undefined && a.userAttendee?.userId === account.user?.id
  );
  const currentAnonRsvp = rsvps.find(
    a => anonymousAuthToken && anonymousAuthToken !== '' && a.anonymousAttendee
      && a.anonymousAttendee?.authToken === anonymousAuthToken
  );

  const editingRsvp = newRsvpMode === 'anonymous' ? currentAnonRsvp
    : newRsvpMode === 'user' ? currentRsvp : undefined;

  const [showRsvpCards, setShowRsvpCards] = useState(false);
  const [loading, setLoading] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [loadFailed, setLoadFailed] = useState(false);

  const numberOfGuestsOptions = [...Array(52).keys()];

  useEffect(() => {
    if (editingRsvp) {
      if (newRsvpMode === 'anonymous') {
        setAnonymousRsvpName(editingRsvp.anonymousAttendee?.name ?? '');
      }
      setNumberOfGuests(editingRsvp.numberOfGuests);
      setPublicNote(editingRsvp.publicNote);
      setPrivateNote(editingRsvp.privateNote);
      setRsvpStatus(editingRsvp.status);
    } else {
      setAnonymousRsvpName('');
      setNumberOfGuests(1);
      setPublicNote('');
      setPrivateNote('');
      setRsvpStatus(RsvpStatus.UNRECOGNIZED);
    }
  }, [newRsvpMode, currentAnonRsvp, currentRsvp]);

  const className = `event-rsvp-manager-${occasion.id}`;
  const showRsvpCardsButtonClassName = `event-rsvp-card-button-${occasion.id}`;
  const formClassName = `event-rsvp-form-${occasion.id}`;
  const topButtonsClassName = 'rsvp-manager-buttons';

  const scrollToRsvps = () => document.querySelectorAll(`.${topButtonsClassName}`)
    .forEach(e => e.scrollIntoView({ block: 'start', inline: 'center', behavior: 'smooth' }));

  const scrollToRsvpForm = () => setTimeout(() =>
    document.querySelectorAll(`.${formClassName}`)
      .forEach(e => e.scrollIntoView({ block: 'center', behavior: 'smooth' })),
    500);

  const [showDetails, setShowDetails] = useState(false);
  useEffect(() => {
    if (!isPreview && querySection === 'rsvp' && loaded) {
      setShowRsvpCards(true);
      setTimeout(() => {
        scrollToRsvps();
      }, 1000);
    }
  }, [querySection, loaded]);
  useEffect(() => {
    if (!isPreview && anonymousAuthToken && anonymousAuthToken !== '') {
      setTimeout(() => {
        setNewRsvpMode?.('anonymous');
      },
        1000)
    }
  }, [anonymousAuthToken]);

  // useEffect(() => {
  //   if (newRsvpMode !== undefined && !isPreview) {
  //     scrollToRsvpForm();
  //   }
  // }, [newRsvpMode]);

  useEffect(() => {
    if (!isPreview || isModalPreview) {
      if (canRsvpNonAnonymously && newRsvpMode === undefined && anonymousAuthToken !== '') {
        setNewRsvpMode?.('user');
      } else if (canRsvpAnonymously && newRsvpMode === undefined) {
        setNewRsvpMode?.('anonymous');
      }
    }
  }, [isPreview, isModalPreview, canRsvpAnonymously, canRsvpNonAnonymously]);

  useEffect(() => {
    if (newRsvpMode === 'anonymous' && !canRsvpAnonymously) {
      setNewRsvpMode?.(undefined);
    } else if (newRsvpMode === 'user' && !canRsvpNonAnonymously) {
      setNewRsvpMode?.(undefined);
    }
  }, [newRsvpMode, canRsvpNonAnonymously, canRsvpAnonymously]);

  const rsvpData = useSelector(selectRsvpData(federateId(occasion.id, event.serverHost)));
  useEffect(() => {
    if (occasion && !loading && !loaded && !rsvpData) {
      setLoading(true);
      dispatch(loadRsvpData({ occasionId: occasion.id, anonymousAttendeeAuthToken: anonymousAuthToken, ...accountOrServer }))
        .finally(() => {
          setLoaded(true);
          setLoading(false);
        });
    }
  }, [rsvpData, accountOrServerId(accountOrServer), event?.id, occasion?.id, loading, anonymousAuthToken]);
  useEffect(() => {
    setRsvps(rsvpData?.rsvps ?? []);
  }, [rsvpData]);

  // useEffect(() => {
  //   if (occasion && !loading && !loaded) {
  //     setLoading(true);
  //     setTimeout(async () => {
  //       try {
  //         // console.log('loading rsvp data with auth token', anonymousAuthToken);
  //         // const client = await getCredentialClient(accountOrServer);
  //         // const eventRsvpsResponse = await client.getRsvps({
  //         //   occasionId: occasion?.id,
  //         //   anonymousAttendeeAuthToken: anonymousAuthToken
  //         // }, client.credential);
  //         // setRsvps(eventRsvpsResponse.rsvps);
  //         // if (event.info?.hideLocationUntilRsvpApproved && !occasion.location && eventRsvpsResponse.hiddenLocation) {
  //         //   // debugger;
  //         //   setTimeout(() => dispatch(saveHiddenLocation({ location: eventRsvpsResponse.hiddenLocation!, event, occasion })), 1000);
  //         // }
  //       } catch (e) {
  //         console.error('Failed to load event rsvps', e)
  //         setLoadFailed(true);
  //       } finally {
  //         setLoaded(true);
  //         setLoading(false);
  //       }
  //     }, 1);

  //     // setLoaded(true);
  //   }
  // }, [accountOrServerId(accountOrServer), event?.id, occasion?.id, loading, anonymousAuthToken]);

  useEffect(() => {
    setLoaded(false);
    // setRsvps([]);
  }, [accountOrServerId(accountOrServer), anonymousAuthToken, event?.id, occasion?.id]);

  const [rsvpStatus, setRsvpStatus] = useState(RsvpStatus.INTERESTED);
  const [anonymousRsvpName, setAnonymousRsvpName] = useState('');
  const [publicNote, setPublicNote] = useState('');
  const [privateNote, setPrivateNote] = useState('');
  const [numberOfGuests, setNumberOfGuests] = useState(1);

  const hasModifiedRsvp = !!editingRsvp && (
    editingRsvp?.status != rsvpStatus ||
    editingRsvp?.numberOfGuests != numberOfGuests ||
    editingRsvp?.publicNote != publicNote ||
    editingRsvp?.privateNote != privateNote ||
    (newRsvpMode === 'anonymous'
      && currentAnonRsvp !== undefined && anonymousRsvpName !== currentAnonRsvp?.anonymousAttendee?.name));
  ;
  const canRsvpWhenStatusSet = ((newRsvpMode === 'user' && account?.user) || anonymousRsvpName.length > 0)
  const rsvpValid = canRsvpWhenStatusSet
    && [RsvpStatus.GOING, RsvpStatus.INTERESTED, RsvpStatus.REQUESTED, RsvpStatus.NOT_GOING,]
      .includes(editingRsvp?.status ?? RsvpStatus.UNRECOGNIZED);
  // const canRsvp = editingRsvp
  //   && rsvpValid;

  const upsertableRsvp = occasion ? {
    occasionId: occasion.id,
    userAttendee: newRsvpMode === 'user'
      ? { userId: account?.user?.id }
      : undefined,
    anonymousAttendee: newRsvpMode === 'anonymous' ? {
      name: anonymousRsvpName,
      authToken: anonymousAuthToken
    } : undefined,
    status: rsvpStatus,
    numberOfGuests: numberOfGuests,
    privateNote,
    publicNote,
  } : undefined;

  const [upserting, setUpserting] = useState(false);
  const [upsertSuccess, setUpsertSuccess] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const busy = upserting || deleting || loading;
  const toast = useToastController();
  async function upsertRsvp(rsvp?: Rsvp) {
    setUpserting(true);
    setUpsertSuccess(false);

    // console.log('upsert status', (rsvp ?? upsertableRsvp)?.status)
    const client = await getCredentialClient(accountOrServer);
    function resetUpserting() {
      setTimeout(() => setUpserting(false), 500);
    }
    return client.upsertRsvp((rsvp ?? upsertableRsvp)!, client.credential).then((result) => {
      // setUpserting(false);
      setUpsertSuccess(true);
      updateRsvp(result);
      toast.show('RSVP saved.', { type: 'success' });

      if (newRsvpMode === 'anonymous') {
        if (result.anonymousAttendee?.authToken) {
          setAnonymousAuthToken(result.anonymousAttendee.authToken);
        }
      } else {
        // setNewRsvpMode?.(undefined);
      }
    }).finally(resetUpserting);
  }

  const pendingUpsertableRsvp = useDebounceValue(upsertableRsvp, 800)
  useEffect(() => {
    if (hasModifiedRsvp && editingRsvp && rsvpValid && !upserting && !deleting) {
      upsertRsvp();
    }
  }, [pendingUpsertableRsvp]);

  function updateRsvp(rsvp: Rsvp) {
    setRsvps([
      rsvp,
      ...rsvps.filter(a => a.id !== rsvp.id)
    ]);
  }

  // const loadedDebounce = useDebounceValue(loaded, 1500);
  // useEffect(() => {
  //   if (!loadedDebounce && rsvps.length > 0) {
  //     setLoaded(true);
  //   }
  // }, [loadedDebounce]);

  const { browseRsvpsFromPreviews } = useLocalConfiguration();
  async function deleteRsvp(rsvp: Rsvp) {
    setDeleting(true);

    const client = await getCredentialClient(accountOrServer);
    client.deleteRsvp({
      occasionId: occasion.id,
      userAttendee: newRsvpMode === 'user'
        ? { userId: account?.user?.id }
        : undefined,
      anonymousAttendee: newRsvpMode === 'anonymous' ? {
        name: anonymousRsvpName,
        authToken: anonymousAuthToken
      } : undefined,
      status: rsvpStatus,
      numberOfGuests: numberOfGuests,
      privateNote,
      publicNote,
    }, client.credential).then((a) => {
      setRsvps([
        ...rsvps.filter(a => a.id !== rsvp.id)
      ]);
      setNewRsvpMode?.(undefined);
      if (rsvp.anonymousAttendee !== undefined) {
        removeAnonymousAuthToken();
      }
    }).finally(() => setDeleting(false));
  }

  const yourRsvps = [currentAnonRsvp, currentRsvp]
    .filter(a => a !== undefined).map(a => a as Rsvp);

  const sortedStatus = (rsvp: Rsvp) =>
  (rsvp.status === RsvpStatus.NOT_GOING
    ? RsvpStatus.UNRECOGNIZED
    : rsvp.status)
  const sortedRsvps = [...rsvps]
    .sort((a, b) => (a.userAttendee ? -1 : 1) - (b.userAttendee ? -1 : 1))
    .sort((a, b) => sortedStatus(b) - sortedStatus(a));

  const nonPendingRsvps = sortedRsvps.filter(a => passes(a.moderation));
  const [goingRsvpCount, goingAttendeeCount] = nonPendingRsvps
    .filter(a => a.status === RsvpStatus.GOING)
    .reduce((acc, a) => [acc[0] + 1, acc[1] + a.numberOfGuests], [0, 0]);
  const [interestedRsvpCount, interestedAttendeeCount] = nonPendingRsvps
    .filter(a => a.status === RsvpStatus.INTERESTED)
    .reduce((acc, a) => [acc[0] + 1, acc[1] + a.numberOfGuests], [0, 0]);
  const [invitedRsvpCount, invitedAttendeeCount] = nonPendingRsvps
    .filter(a => a.status === RsvpStatus.REQUESTED)
    .reduce((acc, a) => [acc[0] + 1, acc[1] + a.numberOfGuests], [0, 0]);

  const pendingRsvps = sortedRsvps.filter(a => pending(a.moderation));
  const [pendingRsvpCount, pendingAttendeeCount] = pendingRsvps
    .reduce((acc, a) => [acc[0] + 1, acc[1] + a.numberOfGuests], [0, 0]);
  const hasPendingRsvps = pendingRsvpCount > 0 || pendingAttendeeCount > 0;

  const rejectedRsvps = sortedRsvps.filter(a => rejected(a.moderation));

  const othersRsvps = nonPendingRsvps.filter(a => [currentRsvp, currentAnonRsvp].every(c => c?.id !== a.id));


  const displayedPendingRsvps = pendingRsvps
    .filter(a => !yourRsvps.some(b => b.id === a.id));
  const displayedRejectedRsvps = rejectedRsvps
    .filter(a => !yourRsvps.some(b => b.id === a.id));
  const displayedOthersRsvps = othersRsvps
    .filter(a => !yourRsvps.some(b => b.id === a.id));

  const mainButtonHeight = '$4';
  const { selectedGroup } = useGroupContext();

  const linkToDetailsPageRsvps = isPreview && !browseRsvpsFromPreviews;
  const linkOccasionId = isPrimaryServer
    ? occasion.id
    : federateId(occasion.id, server);
  const linkGroupShortname = isPrimaryServer
    ? selectedGroup?.shortname
    : federateId(selectedGroup?.shortname ?? '', server);
  const rsvpDetailsBaseLink = selectedGroup
    ? `/g/${linkGroupShortname}/e/${linkOccasionId}?section=rsvp`
    : `/event/${linkOccasionId}?section=rsvp`;
  const rsvpDetailsLinkWithToken = currentAnonRsvp
    ? `${rsvpDetailsBaseLink}&anonymousAuthToken=${currentAnonRsvp.anonymousAttendee?.authToken}`
    : rsvpDetailsBaseLink;
  const rsvpDetailsLink = useLink({ href: rsvpDetailsLinkWithToken });
  const anonymousRsvpPath = `/event/${linkOccasionId}?anonymousAuthToken=${anonymousAuthToken}`;
  const isPast = isPastOccasion(occasion);

  function formatCount(rsvpCount: number, attendeeCount: number,) {
    if (rsvpCount === attendeeCount) {
      return <>{rsvpCount} {rsvpCount === 1 ? 'RSVP' : 'RSVPs'}</>;
    }
    return <>
      {rsvpCount} {rsvpCount === 1 ? 'RSVP' : 'RSVPs'} | {attendeeCount} {attendeeCount === 1 ? 'attendee' : 'attendees'}
    </>;
  }

  if (!occasion) {
    return <></>;
  }

  const editingRsvpPasses = passes(editingRsvp?.moderation);
  const editingRsvpRejected = rejected(editingRsvp?.moderation);

  const canWrite = canRsvpWhenStatusSet && !upserting && !deleting;

  return showRsvpSection
    ?
    <YStack mt={0} mx='$1' px='$1' py='$1' className={className}
      backgroundColor='$backgroundHover' borderRadius='$5'
    >
      <AutoAnimatedList style={{ width: '100%', gap: '4px' }}>
        <XStack w='100%' key='anonymous-and-user-rsvp-buttons' className={topButtonsClassName} gap='$1' //w='100%'
          borderTopLeftRadius='$5' borderTopRightRadius='$5' backgroundColor='$backgroundHover'
          mx='$1'
        >
          {canRsvpNonAnonymously
            ? <Button disabled={busy} opacity={busy ? 0.5 : 1}
              transparent={newRsvpMode != 'user'} h={mainButtonHeight} f={1} p={0} onPress={() => setNewRsvpMode?.(newRsvpMode === 'user' ? undefined : 'user')}>
              <XStack ai='center' gap='$2'>
                {/* {isPreview ? undefined : */}
                <ZStack h='$2' w='$2' my='auto' pt='$5'>
                  <XStack animation='standard' rotate={newRsvpMode === 'user' ? '90deg' : '0deg'}
                    opacity={newRsvpMode === 'user' ? 1 : 0}>
                    <ChevronRight color={primaryAnchorColor} />
                  </XStack>
                  <XStack animation='standard' rotate={newRsvpMode === 'user' ? '45deg' : '0deg'}
                    opacity={!currentRsvp && newRsvpMode !== 'user' ? 1 : 0}>
                    <Plus color={primaryAnchorColor} />
                  </XStack>
                  <XStack animation='standard'
                    opacity={currentRsvp && newRsvpMode !== 'user' ? 1 : 0}>
                    <Edit color={primaryAnchorColor} />
                  </XStack>
                </ZStack>
                {/* } */}
                <Paragraph color={primaryAnchorColor} size='$4' my='auto' f={1} textAlign="center">
                  {currentRsvp ? rsvpName(currentRsvp.status) : 'RSVP'}
                </Paragraph>
              </XStack>
            </Button>
            : undefined}
          {canRsvpAnonymously
            ? <>
              <Button mb='$2' disabled={busy} opacity={busy ? 0.5 : 1}
                transparent={newRsvpMode != 'anonymous'} h={mainButtonHeight} f={1} p={0} onPress={() => setNewRsvpMode?.(newRsvpMode === 'anonymous' ? undefined : 'anonymous')}>
                <XStack ai='center' gap='$2'>
                  {/* {isPreview ? undefined : */}
                  <ZStack h='$2' w='$2'>
                    <XStack animation='standard' rotate={newRsvpMode === 'anonymous' ? '90deg' : '0deg'}
                      opacity={newRsvpMode === 'anonymous' ? 1 : 0}>
                      <ChevronRight color={navAnchorColor} />
                    </XStack>
                    <XStack animation='standard' rotate={newRsvpMode === 'anonymous' ? '45deg' : '0deg'}
                      opacity={!currentAnonRsvp && newRsvpMode !== 'anonymous' ? 1 : 0}>
                      <Plus color={navAnchorColor} />
                    </XStack>
                    <XStack animation='standard'
                      opacity={currentAnonRsvp && newRsvpMode !== 'anonymous' ? 1 : 0}>
                      <Edit color={navAnchorColor} />
                    </XStack>
                  </ZStack>
                  {/* } */}
                  <YStack f={1}>
                    <Paragraph color={navAnchorColor} size='$2' mx='auto'>Anonymously</Paragraph>
                    <Paragraph color={navAnchorColor} size='$1' mx='auto'>
                      {currentAnonRsvp ? rsvpName(currentAnonRsvp.status) : 'RSVP'}
                    </Paragraph>
                  </YStack>
                </XStack>
              </Button>
            </>
            : undefined}
        </XStack>
        {/* } */}
        {/* <AnimatePresence> */}
        {newRsvpMode !== undefined
          ? <>
            {newRsvpMode === 'anonymous'
              ? <YStack key='anonymous-rsvp-header' gap='$2' mx='$2' w='100%' >
                {anonymousAuthToken && anonymousAuthToken.length > 0 && !currentAnonRsvp
                  ? <Paragraph size='$2' mx='$4' mb='$2' als='center' ta='center'>
                    Your anonymous RSVP token was not found. Check the link you used to get here, or just create a new anonymous RSVP.
                  </Paragraph>
                  : undefined}
                <XStack >
                  <Input textContentType="name" f={1}
                    my='$1'
                    placeholder={`Anonymous Guest Name (required)`}
                    /*disabled={busy}*/ o={/*busy ||*/ anonymousRsvpName == '' ? 0.5 : 1}
                    // autoCapitalize='words'
                    value={anonymousRsvpName}
                    onChange={(data) => { setAnonymousRsvpName(data.nativeEvent.text) }} />
                </XStack>
              </YStack>
              : undefined}

            <Button h='auto' key='attendees-notes-button' w='100%' mx='$2'
              mt={editingRsvpRejected ? 0 : -3}
              onPress={() => setShowDetails(!showDetails)}
              mb={showDetails ? '$2' : 0}>
              <XStack ai='center' w='100%'>
                <Heading size='$2' my='auto'>Attendees & Notes</Heading>
                <XStack my='auto' mr='auto' animation='standard' rotate={showDetails ? '90deg' : '0deg'}>
                  <ChevronRight size='$1' />
                </XStack>
              </XStack>
            </Button>

            {showDetails
              ? <YStack className={formClassName} key='rsvp-details' gap='$2' w='100%' mx='$2'>
                <Select native onValueChange={v => setNumberOfGuests(parseInt(v))} value={numberOfGuests.toString()}>
                  <Select.Trigger w='100%' f={1} iconAfter={ChevronDown}>
                    <Select.Value w='100%' placeholder="Choose Visibility" />
                  </Select.Trigger>

                  <Select.Content zIndex={200000}>
                    <Select.Viewport minWidth={200} w='100%'>
                      <XStack w='100%'>
                        <Select.Group gap="$0" w='100%'>
                          {numberOfGuestsOptions.map(i => i + 1).map((item, i) => {
                            return (
                              <Select.Item
                                debug="verbose"
                                index={i}
                                key={item.toString()}
                                value={item.toString()}
                              >
                                <Select.ItemText>{item} {item === 1 ? 'attendee' : 'attendees'}</Select.ItemText>
                                <Select.ItemIndicator marginLeft="auto">
                                  <Check size={16} />
                                </Select.ItemIndicator>
                              </Select.Item>
                            )
                          })}
                        </Select.Group>
                        <YStack
                          position="absolute"
                          right={0}
                          top={0}
                          bottom={0}
                          alignItems="center"
                          justifyContent="center"
                          width={'$4'}
                          pointerEvents="none"
                        >
                          <ChevronDown size='$2' />
                        </YStack>
                      </XStack>
                    </Select.Viewport>
                  </Select.Content>
                </Select>

                <TextArea f={1} pt='$2' my='$1' value={publicNote}
                    /*disabled={busy}*/ opacity={/*busy ||*/ publicNote == '' ? 0.5 : 1}
                  h={(publicNote?.length ?? 0) > 300 ? window.innerHeight - 100 : undefined}
                  onChangeText={setPublicNote}
                  placeholder={`Public note (optional). Markdown is supported.`} />

                <TextArea f={1} pt='$2' my='$1' value={privateNote}
                    /*disabled={busy}*/ opacity={/*busy ||*/ privateNote == '' ? 0.5 : 1}
                  h={(privateNote?.length ?? 0) > 300 ? window.innerHeight - 100 : undefined}
                  onChangeText={setPrivateNote}
                  placeholder={`Private note for the event owner (optional). Markdown is supported.`} />
              </YStack>
              : undefined}



            {newRsvpMode === 'anonymous' && !currentAnonRsvp//!anonymousAuthToken
              ? //<Paragraph size='$1' mx='auto' my='$1' ta='left' maw={500}>
              // <Text fontFamily='$body' fontSize='$1' mr='$4'>{'• '}
              <YStack mx='auto' key='anonymous-rsvp-details'>
                <XStack mb='$2' ai='center'>
                  <Text fontFamily='$body' fontSize='$1' mr='$2'>•</Text>
                  <Text fontFamily='$body' fontSize='$1'>You will be assigned a private RSVP link.
                  </Text>
                </XStack>
                <XStack mb='$2' ai='center'>
                  <Text fontFamily='$body' fontSize='$1' mr='$2'>•</Text>
                  <Text fontFamily='$body' fontSize='$1'>Use it to edit or delete your RSVP later.
                  </Text>
                </XStack>
                <XStack mb='$2' ai='center'>
                  <Text fontFamily='$body' fontSize='$1' mr='$2'>•</Text>
                  <Text fontFamily='$body' fontSize='$1'>Save it in your browser bookmarks, notes app, or calendar app of choice.
                  </Text>
                </XStack>
              </YStack>
              //{/* You will be assigned a unique RSVP link.
              // Use it to edit or delete your RSVP later.
              //   Save it in your browser bookmarks, notes app, or calendar app of choice. */}
              //   {/* </Paragraph> */}
              : undefined}

            <XStack maw='100%' key='going-maybe-notgoing' mx='auto' ai='center' gap='$1'>
              <Tooltip>
                <Tooltip.Trigger>
                  <XStack f={1} ai='center'>
                    <RadioGroup aria-labelledby="Do you plan to attend?" defaultValue={rsvpStatus.toString()}
                      w='100%'
                      disabled={!canRsvpWhenStatusSet || busy}
                      opacity={!canRsvpWhenStatusSet || busy ? 0.5 : 1}
                      onValueChange={v => {
                        setRsvpStatus(parseInt(v));

                        if (canWrite) {
                          upsertRsvp({ ...upsertableRsvp as Rsvp, status: parseInt(v) })
                            .then(() => !currentRsvp && !currentAnonRsvp
                              ? setShowRsvpCards(true)
                              : undefined)
                          // setTimeout(upsertRsvp, 200);
                        }
                      }}
                      // mb='$1'
                      value={rsvpStatus.toString()} name="form" >
                      <XStack ai="center" jc='space-evenly' w='100%' gap="$2" flexWrap="wrap">
                        <RadioGroupItemWithLabel color={primaryAnchorColor} size="$3"
                          onClick={hasModifiedRsvp && rsvpStatus == RsvpStatus.GOING && canWrite ? () => upsertRsvp(Rsvp.create(upsertableRsvp)) : undefined}
                          {...valueAndLabel(RsvpStatus.GOING)} />
                        <RadioGroupItemWithLabel color={navAnchorColor} size="$3"
                          onClick={hasModifiedRsvp && rsvpStatus == RsvpStatus.INTERESTED && canWrite ? () => upsertRsvp(Rsvp.create(upsertableRsvp)) : undefined}
                          {...valueAndLabel(RsvpStatus.INTERESTED)} />
                        <RadioGroupItemWithLabel size="$3"
                          onClick={hasModifiedRsvp && rsvpStatus == RsvpStatus.NOT_GOING && canWrite ? () => upsertRsvp(Rsvp.create(upsertableRsvp)) : undefined}
                          {...valueAndLabel(RsvpStatus.NOT_GOING)} />
                      </XStack>
                    </RadioGroup>
                  </XStack>
                </Tooltip.Trigger>
                {canRsvpWhenStatusSet
                  ? undefined
                  : <Tooltip.Content>
                    <Paragraph>
                      {newRsvpMode === 'anonymous'
                        ? 'Enter a name to RSVP anonymously.'
                        : 'Log in to RSVP.'}
                    </Paragraph>
                  </Tooltip.Content>
                }
              </Tooltip>
              <Tooltip>
                <Tooltip.Trigger>
                  <ZStack w='$2' h='$2' my='auto' mx='auto'
                    jc='center' ai='center' ac='center'
                  // borderRadius='$4' backgroundColor='$backgroundStrong'
                  >
                    <XStack animation='standard' o={hasModifiedRsvp && !busy ? 1 : 0} mx='auto' my='auto'>
                      <AlertCircle />
                    </XStack>
                    <XStack animation='standard' o={busy ? 1 : 0} mx='auto' my='auto'>
                      <Spinner size='small' />
                    </XStack>
                    <XStack animation='standard' o={editingRsvp && editingRsvpPasses && !editingRsvpRejected && !(hasModifiedRsvp || busy) ? 1 : 0} mx='auto' my='auto'>
                      <CheckCircle color={primaryAnchorColor} />
                    </XStack>

                    <XStack animation='standard' o={editingRsvp && !editingRsvpPasses && !editingRsvpRejected && !(hasModifiedRsvp || busy) ? 1 : 0}
                      mx='auto' my='auto'>
                      <ShieldAlert color={navAnchorColor} />
                    </XStack>

                    <XStack animation='standard' o={editingRsvp && editingRsvpRejected && !(hasModifiedRsvp || busy) ? 1 : 0}
                      mx='auto' my='auto'>
                      <AlertTriangle color={undefined} />
                    </XStack>

                  </ZStack>
                </Tooltip.Trigger>
                {!busy && (hasModifiedRsvp || (upsertSuccess && editingRsvp) || editingRsvp && !passes(editingRsvp.moderation))
                  ? <Tooltip.Content>
                    <Paragraph>
                      {hasModifiedRsvp
                        ? 'RSVP has unsaved changes.'
                        : editingRsvpPasses
                          ? 'RSVP saved.'
                          : editingRsvpRejected
                            ? 'RSVP rejected by event owner. Please update your RSVP to re-submit for approval.'
                            : 'RSVP saved. Hidden from others until event owner approves.'}
                    </Paragraph>
                  </Tooltip.Content>
                  : undefined}
              </Tooltip>
            </XStack>

            {editingRsvpRejected ? <Paragraph key={`rsvp-moderation-description-${editingRsvp?.moderation}`} size='$3' mx='auto' my='$1' ta='left' maw={500} fontWeight='bold'>
              {rsvpModerationDescription(editingRsvp!.moderation)}
            </Paragraph>
              : undefined}

            {newRsvpMode === 'anonymous' && anonymousAuthToken && anonymousAuthToken.length > 0 && currentAnonRsvp
              ? <YStack key='anonymous-rsvp-link'>
                <Paragraph size={isPreview ? '$2' : '$4'} mx='$4' mb='$2' als='center' ta='center'>
                  Save <Anchor href={anonymousRsvpPath} color={navAnchorColor} target='_blank'>this private RSVP link</Anchor> to update your RSVP later.
                </Paragraph>
                <XStack mx='auto'>
                  <EventCalendarExporter event={event} occasion={occasion} tiny={false} />
                </XStack>
              </YStack>
              : undefined}

            <XStack key='new-anonymous-or-delete' w='100%' gap='$2'>

              {newRsvpMode === 'anonymous' && anonymousAuthToken && anonymousAuthToken.length > 0
                ? <>
                  <Dialog>
                    <Dialog.Trigger asChild>
                      <Button f={1} transparent mx='auto' color={navAnchorColor} disabled={busy} opacity={!busy ? 1 : 0.5}>
                        New RSVP
                      </Button>
                    </Dialog.Trigger>
                    <Dialog.Portal zi={1000011}>
                      <Dialog.Overlay
                        key="overlay"
                        animation='standard'
                        o={0.5}
                        enterStyle={{ o: 0 }}
                        exitStyle={{ o: 0 }}
                      />
                      <Dialog.Content
                        bordered
                        elevate
                        key="content"
                        animation={[
                          'standard',
                          {
                            opacity: {
                              overshootClamping: true,
                            },
                          },
                        ]}
                        m='$3'
                        enterStyle={{ x: 0, y: -20, opacity: 0, scale: 0.9 }}
                        exitStyle={{ x: 0, y: 10, opacity: 0, scale: 0.95 }}
                        x={0}
                        scale={1}
                        opacity={1}
                        y={0}
                      >
                        <YStack space>
                          <Dialog.Title>New Anonymous RSVP</Dialog.Title>
                          <Dialog.Description>
                            Make sure you've saved <Anchor href={anonymousRsvpPath} color={navAnchorColor} target='_blank'>this private RSVP link</Anchor> to update/delete your current RSVP later!
                          </Dialog.Description>

                          <XStack gap="$3" jc="flex-end">
                            <Dialog.Close asChild>
                              <Button>Cancel</Button>
                            </Dialog.Close>
                            <Dialog.Close asChild>
                              {/* <Theme inverse> */}
                              <Button color={primaryAnchorColor}
                                onPress={removeAnonymousAuthToken}>
                                Create
                              </Button>
                              {/* </Theme> */}
                            </Dialog.Close>
                          </XStack>
                        </YStack>
                      </Dialog.Content>
                    </Dialog.Portal>
                  </Dialog>
                </>
                : undefined}
              {editingRsvp //&& !isPreview
                ? <Dialog>
                  <Dialog.Trigger asChild>
                    <Button f={1} disabled={busy} opacity={!busy ? 1 : 0.5}>
                      Delete
                    </Button>
                  </Dialog.Trigger>
                  <Dialog.Portal zi={1000011}>
                    <Dialog.Overlay
                      key="overlay"
                      animation='standard'
                      o={0.5}
                      enterStyle={{ o: 0 }}
                      exitStyle={{ o: 0 }}
                    />
                    <Dialog.Content
                      bordered
                      elevate
                      key="content"
                      animation={[
                        'standard',
                        {
                          opacity: {
                            overshootClamping: true,
                          },
                        },
                      ]}
                      m='$3'
                      enterStyle={{ x: 0, y: -20, opacity: 0, scale: 0.9 }}
                      exitStyle={{ x: 0, y: 10, opacity: 0, scale: 0.95 }}
                      x={0}
                      scale={1}
                      opacity={1}
                      y={0}
                    >
                      <YStack space>
                        <Dialog.Title>Delete RSVP</Dialog.Title>
                        <Dialog.Description>
                          Really delete this RSVP?
                        </Dialog.Description>

                        <XStack gap="$3" jc="flex-end">
                          <Dialog.Close asChild>
                            <Button>Cancel</Button>
                          </Dialog.Close>
                          <Dialog.Close asChild>
                            {/* <Theme inverse> */}
                            <Button color={primaryAnchorColor}
                              onPress={() => deleteRsvp(editingRsvp)}>
                              Delete
                            </Button>
                            {/* </Theme> */}
                          </Dialog.Close>
                        </XStack>
                      </YStack>
                    </Dialog.Content>
                  </Dialog.Portal>
                </Dialog>
                : undefined}
            </XStack>
          </>
          : undefined}
        <Button key='rsvp-card-toggle' w='100%'
          className={showRsvpCardsButtonClassName}
          borderRadius='$1'
          // mt={isPreview ? undefined : '$2'}
          // mt='$1'
          h='auto'
          // {hasPendingRsvps
          //   ? (mediaQuery.gtXxxxs ? '$10' : '$15')
          //   : (mediaQuery.gtXxxxs ? '$5' : '$10')}
          {...linkToDetailsPageRsvps ? rsvpDetailsLink : {}}
          onPress={linkToDetailsPageRsvps
            ? undefined
            : () => setShowRsvpCards(!showRsvpCards)}
          disabled={rsvps.length === 0} o={rsvps.length === 0 ? 0.5 : 1}>
          <XStack w='100%'>
            <YStack f={1}>
              {hasPendingRsvps
                ? <XStack w='100%' flexWrap="wrap">
                  <Paragraph size='$1' fontWeight='700'>{isPreview ? 'Pending' : isEventOwner ? 'Pending Your Approval' : 'Pending Owner Approval'}</Paragraph>
                  <Paragraph size='$1' ml='auto'>
                    {formatCount(pendingRsvpCount, pendingAttendeeCount)}
                  </Paragraph>
                </XStack>
                : undefined}
              {goingRsvpCount > 0 ||
                (!hasPendingRsvps && interestedRsvpCount === 0 && invitedRsvpCount === 0)
                ? <XStack w='100%' flexWrap="wrap">
                  <Paragraph size='$1' color={primaryAnchorColor}>Going</Paragraph>
                  {loadFailed
                    ? <XStack ml='auto' my='auto'><AlertTriangle size='$1' /></XStack>
                    : <Paragraph size='$1' ml='auto'>
                      {formatCount(goingRsvpCount, goingAttendeeCount)}
                    </Paragraph>}
                </XStack>
                : undefined}
              {interestedRsvpCount > 0
                ? <XStack w='100%' flexWrap="wrap">
                  <Paragraph size='$1' color={navAnchorColor}>Interested</Paragraph>
                  <Paragraph size='$1' ml='auto'>
                    {formatCount(interestedRsvpCount, interestedAttendeeCount)}
                  </Paragraph>
                </XStack> : undefined}
              {invitedRsvpCount > 0
                ? <XStack w='100%' flexWrap="wrap">
                  <Paragraph size='$1' color={navAnchorColor}>Invited</Paragraph>
                  <Paragraph size='$1' ml='auto'>
                    {formatCount(invitedRsvpCount, invitedAttendeeCount)}
                  </Paragraph>
                </XStack>
                : undefined}
            </YStack>
            <XStack animation='standard' my='auto' ml='$2' rotate={showRsvpCards ? '90deg' : '0deg'}>
              <ChevronRight />
            </XStack>
          </XStack>
        </Button>
        {showRsvpCards
          ? <YStack key='rsvp-cards' gap='$2' w='100%'
            borderBottomLeftRadius='$5' borderBottomRightRadius='$5' backgroundColor='$backgroundHover'
            px='$1'>
            <AnimatePresence>
              {loadFailed
                ? <AlertTriangle key='error' />
                : undefined}

              {currentRsvp || currentAnonRsvp
                ? <Heading size='$6' mx='auto' key='your-rsvps'>
                  Your {yourRsvps.length !== 1 ? 'RSVPs' : 'RSVP'}
                </Heading>
                : undefined}
              {currentAnonRsvp //&& newRsvpMode !== 'anonymous'
                ? //<Theme inverse={newRsvpMode === 'anonymous'}>
                <RsvpCard key={`current-anon-rsvp-${currentAnonRsvp.anonymousAttendee?.authToken}`}
                  rsvp={currentAnonRsvp}
                  event={event}
                  occasion={occasion}
                  onPressEdit={() => {
                    setNewRsvpMode?.('anonymous');
                    // setTimeout(() => scrollToRsvpForm(), 1000);
                    // document.querySelectors rsvp-manager-buttons')?.scrollIntoView({ block: 'start', behavior: 'smooth' });
                  }}
                  onModerated={updateRsvp}
                />
                //</Theme>
                : undefined}
              {currentRsvp //&& newRsvpMode !== 'user'
                ? //<Theme inverse={newRsvpMode === 'user'}>
                <RsvpCard key={`current-rsvp-${currentRsvp.userAttendee?.userId}`}
                  rsvp={currentRsvp}
                  event={event}
                  occasion={occasion}
                  onPressEdit={() => {
                    setNewRsvpMode?.('user');
                    // setTimeout(() => scrollToRsvpForm(), 1000);
                    // document.querySelector('.rsvp-manager-buttons')?.scrollIntoView({ block: 'start', behavior: 'smooth' });
                  }}
                  onModerated={updateRsvp}
                />
                //</Theme>
                : undefined}

              {displayedPendingRsvps.length > 0
                ? <Heading size='$6' mx='auto' key='pending-rsvps' pb='$1'>Pending RSVPs</Heading>
                : undefined}
              {displayedPendingRsvps.map((rsvp, index) => {
                return <RsvpCard key={`pending-rsvp-${rsvp.userAttendee?.userId ?? index}`}
                  rsvp={rsvp}
                  event={event}
                  occasion={occasion}
                  onModerated={updateRsvp}
                />;
              })}

              {displayedOthersRsvps.length > 0 && (account || anonymousAuthToken)
                ? <Heading size='$6' mx='auto' key='other-rsvps'
                  pb='$1'>Others' RSVPs</Heading>
                : undefined}
              {displayedOthersRsvps.map((rsvp, index) => {
                return <RsvpCard key={`non-pending-rsvp-${rsvp.userAttendee?.userId ?? index}`}
                  rsvp={rsvp}
                  event={event}
                  occasion={occasion}
                  onModerated={updateRsvp}
                />;
              })}

              {displayedRejectedRsvps.length > 0
                ? <Heading size='$6' mx='auto' key='rejected-rsvps' pb='$1'>Rejected RSVPs</Heading>
                : undefined}
              {displayedRejectedRsvps.map((rsvp, index) => {
                return <RsvpCard key={`rejected-rsvp-${rsvp.userAttendee?.userId ?? index}`}
                  rsvp={rsvp}
                  event={event}
                  occasion={occasion}
                  onModerated={updateRsvp}
                />;
              })}
            </AnimatePresence>
          </YStack>
          : undefined}
        {/* </AnimatePresence> */}
      </AutoAnimatedList>
    </YStack>
    : <></>;
};

let _key = 1;
export function RadioGroupItemWithLabel(props: {
  size: SizeTokens
  value: string
  label: string
  color?: string
  onClick?: () => void
}) {
  const id = useComponentKey('radio-group-item');
  return (
    <XStack f={1} alignItems="center" gap="$2">
      <RadioGroup.Item value={props.value} id={id} size={props.size} onClick={props.onClick}>
        <RadioGroup.Indicator />
      </RadioGroup.Item>

      <Label size={props.size} htmlFor={id} color={props.color}>
        {props.label}
      </Label>
    </XStack>
  )
}

function valueAndLabel(value: RsvpStatus, isPast: boolean = false) {
  return { value: value.toString(), label: rsvpName(value, isPast) as string };
}
function rsvpName(rsvpStatus: RsvpStatus, isPast: boolean = false) {
  switch (rsvpStatus) {
    case RsvpStatus.GOING:
      return isPast ? 'Went' : 'Going';
    case RsvpStatus.INTERESTED:
      return 'Interested';
    case RsvpStatus.NOT_GOING:
      return isPast ? "Didn't Go" : 'Not Going';
    case RsvpStatus.REQUESTED:
      return 'Invited';
    default:
      return 'Unknown';
  }
}
