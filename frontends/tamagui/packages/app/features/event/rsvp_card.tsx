import { useFederatedDispatch } from "app/hooks";
import { FederatedEvent, getCredentialClient, useServerTheme } from "app/store";
import React, { useState } from "react";

import { RsvpStatus, Rsvp, Occasion, Moderation, Post } from "@rellm/api";
import { Button, Card, Heading, Paragraph, XStack, YStack, standardAnimation, useMedia } from "@rellm/ui";
import { Edit3 as Edit } from "@tamagui/lucide-icons";
import { ModerationPicker } from "app/components/moderation_picker";
import { AccountOrServerContextProvider } from "app/contexts";
import { passes } from "app/utils/moderation_utils";
import { TamaguiMarkdown } from "app/components/tamagui_markdown";
import { AuthorInfo } from "../post/author_info";

interface Props {
  event: FederatedEvent;
  occasion: Occasion;
  rsvp: Rsvp;
  onPressEdit?: () => void;
  onModerated?: (rsvp: Rsvp) => void;
}

export const RsvpCard: React.FC<Props> = ({
  event,
  occasion,
  rsvp,
  onPressEdit,
  onModerated,
}) => {
  const mediaQuery = useMedia();
  const { dispatch, accountOrServer } = useFederatedDispatch(event);
  const { account } = accountOrServer;
  const isEventOwner = account && account?.user?.id === event?.post?.author?.userId;
  // const post = event.post!;

  const { server, textColor, primaryColor, navAnchorColor: navColor, backgroundColor: themeBgColor, primaryAnchorColor, navAnchorColor } = useServerTheme();

  const { anonymousAttendee, userAttendee, publicNote, privateNote, status, numberOfGuests } = rsvp;

  const [upserting, setUpserting] = useState(false);
  async function applyModeration(moderation: Moderation) {
    setUpserting(true);

    const client = await getCredentialClient(accountOrServer);
    client.upsertRsvp({ ...rsvp, moderation }, client.credential)
      .then(onModerated)
      .finally(() => setUpserting(false));
  }

  // console.log('rsvp.userAttendee', rsvp.userAttendee);
  return <Card elevate size="$4" bordered
    animation='standard'
    {...standardAnimation}
    key={`rsvp-card-${rsvp.id}`}
    margin='$0'
    mx="$1"
    scale={1}
    // opacity={1}
    y={0}
    mb='$2'
  >
    <Card.Header pb={0}>
      <XStack>
        <YStack f={1}>
          {anonymousAttendee
            ? <>
              <Paragraph size='$1'>Anonymous</Paragraph>
              <Heading size='$7'>{anonymousAttendee.name}</Heading>
            </>
            : <AccountOrServerContextProvider value={accountOrServer}>
              <AuthorInfo larger post={Post.create({ author: rsvp.userAttendee! })} />
            </AccountOrServerContextProvider>}
        </YStack>
        <YStack my='auto'>
          <Paragraph size='$2' mx='auto'
            color={rsvp.status == RsvpStatus.GOING ? primaryAnchorColor :
              rsvp.status == RsvpStatus.INTERESTED || rsvp.status == RsvpStatus.REQUESTED ? navAnchorColor : undefined}>
            {rsvpStatusString(rsvp.status)}
          </Paragraph>
          {/* {rsvp.numberOfGuests > 1 ? */}
          <Paragraph size='$1' mx='auto'>
            {rsvp.numberOfGuests} attendee{rsvp.numberOfGuests > 1 ? 's' : ''}
          </Paragraph>
          {/* : undefined} */}
        </YStack>
        {onPressEdit
          ? <Button circular transparent icon={Edit} onClick={onPressEdit} />
          : undefined}
      </XStack>
    </Card.Header>
    <Card.Footer p='$3' pr={mediaQuery.gtXs ? '$3' : '$1'} pt={0}>
      <YStack w='100%'>
        <TamaguiMarkdown text={publicNote} />
        {privateNote && privateNote.length > 0
          ? <>
            <Heading size='$1'>Private Note</Heading>
            <TamaguiMarkdown text={privateNote} />
          </>
          : undefined}
        <XStack ml='auto'>
          {/* <XStack f={1} /> */}
          {isEventOwner ?
            <ModerationPicker moderation={rsvp.moderation}
              moderationDescription={rsvpModerationDescription}
              disabled={upserting}
              onChange={applyModeration} />
            : !passes(rsvp.moderation)
              ? <Paragraph size='$1' ml='auto'>{rsvpModerationDescription(rsvp.moderation)}</Paragraph>
              : undefined}
        </XStack>
      </YStack>
    </Card.Footer>
  </Card>;
};



export function rsvpModerationDescription(v: Moderation) {
  switch (v) {
    case Moderation.UNMODERATED: return 'Visible to anyone who can view this event.';
    case Moderation.REJECTED: return 'Rejected by the event owner. Visible only to attendee and owner.';
    case Moderation.APPROVED: return 'Visible to anyone who can view the event.';
    case Moderation.PENDING: return 'Awaiting approval by the event owner. Visible only to attendee and owner.';
  }
}

const rsvpStatusString = (status: RsvpStatus) => {
  switch (status) {
    case RsvpStatus.GOING:
      return 'Going';
    case RsvpStatus.INTERESTED:
      return 'Interested';
    case RsvpStatus.REQUESTED:
      return 'Requested';
    case RsvpStatus.NOT_GOING:
      return 'Not Going';
    default:
      return 'Unknown';
  }
}

export default RsvpCard;
