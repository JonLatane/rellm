import { FederatedPost, deletePost, federateId, loadPostReplies, selectPostById, updatePost, useServerTheme } from "app/store";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import { GestureResponderEvent, View } from "react-native";

import { Post, PostContext, Visibility } from "@rellm/api";
import { Anchor, AnimatePresence, Button, Card, Dialog, Heading, Image, Paragraph, Text, TamaguiMediaState, TextArea, Theme, XStack, YStack, reverseStandardAnimation, standardAnimation, useMedia, useToastController, useDebounceValue } from '@rellm/ui';
import { ChevronRight, Delete, Edit3 as Edit, Eye, Link, Link2, Reply, Save, X as XIcon } from "@tamagui/lucide-icons";
import { FadeInView, TamaguiMarkdown } from "app/components";
import { FacebookEmbed, InstagramEmbed, LinkedInEmbed, PinterestEmbed, TikTokEmbed, TwitterEmbed, YouTubeEmbed } from 'react-social-media-embed';
import { useLink } from "solito/link";
import { AuthorInfo } from "./author_info";

import { ShareableToggle, VisibilityPicker } from "app/components";
import { AccountOrServerContextProvider, useGroupContext } from "app/contexts";
import { GroupPostManager } from 'app/features/groups/group_post_manager';
import { ServerNameAndLogo } from "app/features/navigation/server_name_and_logo";
import { useAppSelector, useComponentKey, useCurrentAccountOrServer, useIsVisible, useLocalConfiguration, useMediaUrl, usePinnedAccountsAndServers, usePostDispatch } from "app/hooks";
import { federatedEntity, serverHost } from 'app/store/federation';
import { isImageMedia } from "app/utils";
import { postVisibilityDescription } from "./base_create_post_sheet";
import { PostMediaManager } from "./post_media_manager";
import { LinkProps, PostMediaRenderer } from "./post_media_renderer";
import { StarButton } from "./star_button";

interface PostCardProps {
  // Note: Post may not be a FederatedPost if the Post is a reply. This could be better thought out...
  // it might be better to make a "ReplyCard" type.
  post: Post;
  isPreview?: boolean;
  // groupContext?: Group;
  replyPostIdPath?: string[];
  collapseReplies?: boolean;
  toggleCollapseReplies?: () => void;
  onLoadReplies?: () => void;
  previewParent?: Post;
  onPress?: () => void;
  onPressParentPreview?: () => void;
  selectedPostId?: string;
  onPressReply?: () => void;
  onEditingChange?: (editing: boolean) => void;
  forceExpandPreview?: boolean;
  forceShrinkPreview?: boolean;
  isSubjectPost?: boolean;
  showPermalink?: boolean;
}

export const postBackgroundSize = (media: TamaguiMediaState) =>
  media.gtLg ? 800 : media.gtMd ? 800 : media.gtSm ? 800 : media.gtXs ? 600 : 500;

export const PostCard: React.FC<PostCardProps> = ({
  post: unfederatedPost,
  isPreview,
  // groupContext,
  replyPostIdPath,
  toggleCollapseReplies,
  onLoadReplies,
  collapseReplies,
  previewParent,
  onPress,
  onPressParentPreview,
  selectedPostId,
  onPressReply,
  onEditingChange,
  forceExpandPreview,
  forceShrinkPreview,
  isSubjectPost,
  showPermalink
}) => {
  const mediaQuery = useMedia();
  const { dispatch, accountOrServer } = usePostDispatch(unfederatedPost);
  const currentUser = accountOrServer.account?.user;
  const server = accountOrServer.server;
  const federatedPostId = federateId(unfederatedPost.id, server);

  // For replies, as users may update them, we ultimately want to
  // source the post from the store, necessarily the Post/Reply hierarchy.
  const updatedPost = useAppSelector(state => selectPostById(state.posts, federatedPostId));
  const post: FederatedPost = { ...(updatedPost ?? unfederatedPost), serverHost: serverHost(server) };
  const isReply = post.context === PostContext.REPLY;

  const isPrimaryServer = useCurrentAccountOrServer().server?.host === accountOrServer.server?.host;
  const currentAndPinnedServers = usePinnedAccountsAndServers();
  const showServerInfo = ('serverHost' in post) && (!isPrimaryServer || (isPreview && currentAndPinnedServers.length > 1));

  const shrinkServerInfo = !mediaQuery.gtXxxs || (isPreview && (!mediaQuery.gtXxxs || forceShrinkPreview));
  // console.log('PostCard', post.id, serverHost, accountOrServer?.server?.host);

  const { selectedGroup } = useGroupContext();
  const isGroupPrimaryServer = useCurrentAccountOrServer().server?.host === selectedGroup?.serverHost;

  const { primaryColor, primaryTextColor, primaryBgColor, primaryAnchorColor, navAnchorColor } = useServerTheme(server);
  // const postsStatus = useRootSelector((state: RootState) => state.posts.status);
  const [editing, _setEditing] = useState(false);
  const setEditing = useCallback((value: boolean) => {
    _setEditing(value);
    onEditingChange?.(value);
  }, [onEditingChange]);
  const toast = useToastController();
  const [previewingEdits, setPreviewingEdits] = useState(false);
  const [savingEdits, setSavingEdits] = useState(false);
  // const savingEditsDebounce = useDebounceValue(savingEdits, 500);

  const [editedContent, setEditedContent] = useState(post.content);
  const [editedMedia, setEditedMedia] = useState(post.media);
  const [editedEmbedLink, setEditedEmbedLink] = useState(post.embedLink);
  const [editedVisibility, setEditedVisibility] = useState(post.visibility);
  const [editedShareable, setEditedShareable] = useState(post.shareable);

  const content = editing ? editedContent : post.content;
  const media = editing ? editedMedia : post.media;
  const embedLink = editing ? editedEmbedLink : post.embedLink;
  const visibility = editing ? editedVisibility : post.visibility;
  const shareable = editing ? editedShareable : post.shareable;
  const { imagePostBackgrounds, fancyPostBackgrounds, shrinkPreviews: appShrinkPreviews } = useLocalConfiguration();

  const saveEdits = useCallback(() => {
    if (savingEdits) return;

    requestAnimationFrame(() => {
      setSavingEdits(true);
      console.log('saveEdits replyPostIdPath', replyPostIdPath);
      dispatch(updatePost({
        ...accountOrServer, ...post,
        content: editedContent,
        media: editedMedia,
        embedLink: editedEmbedLink,
        visibility: editedVisibility,
        shareable: editedShareable,
        postIdPath: replyPostIdPath
      }))
        .then(() => requestAnimationFrame(() => {
          setEditing(false);
          setPreviewingEdits(false);
        }))
        .finally(() => requestAnimationFrame(() => {
          setSavingEdits(false);
        }));

    })
  }, [savingEdits, accountOrServer, post, editedContent, editedMedia, editedEmbedLink, editedVisibility, editedShareable, replyPostIdPath, dispatch]);

  const [deleted, setDeleted] = useState(post.author === undefined);
  const [deleting, setDeleting] = useState(false);
  const doDeletePost = useCallback(() => {
    setDeleting(true);
    dispatch(deletePost({ ...accountOrServer, ...post })).then(() => {
      setDeleted(true);
      setDeleting(false);
    });
  }, [accountOrServer, post, dispatch]);

  const ref = React.useRef(undefined as never) as React.MutableRefObject<HTMLElement | View>;
  const isVisible = useIsVisible(ref);

  const postHasWebLink = useMemo(() => !!post.link && post.link.startsWith('http'), [post.link]);

  const webLink = useLink({
    href: post.link ?? '',
  });
  const postLink = postHasWebLink ? webLink : undefined;

  const postLinkView = useMemo(() => postHasWebLink
    ? <Anchor key='post-link' textDecorationLine='none' {...postLink} target="_blank">
      <XStack>
        <YStack my='auto' mr='$1'>
          <Link size='$1' color={navAnchorColor} />
        </YStack>
        <YStack f={1} my='auto'>
          <Paragraph size="$2" color={navAnchorColor} overflow="hidden" whiteSpace="nowrap" textOverflow="ellipsis">
            {post.link}
          </Paragraph>
        </YStack>
      </XStack>
    </Anchor>
    : undefined, [postHasWebLink, postLink, navAnchorColor, post.link]);

  const detailsLinkId = useMemo(() => !isPrimaryServer
    ? federateId(post.id, accountOrServer.server)
    : post.id, [isPrimaryServer, post.id, accountOrServer.server]);

  const detailsGroupId = useMemo(() => selectedGroup
    ? (!isGroupPrimaryServer
      ? federateId(selectedGroup.shortname, accountOrServer.server)
      : selectedGroup.shortname)
    : undefined, [selectedGroup, isGroupPrimaryServer, accountOrServer.server]);

  const onPressDetails = useMemo(() => onPress
    ? { onPress, accessibilityRole: "link" } as LinkProps
    : undefined, [onPress]);

  const detailsPostLink = useLink({
    href: selectedGroup
      ? `/g/${detailsGroupId || 'missing-id'}/p/${detailsLinkId || 'missing-id'}`
      : `/post/${detailsLinkId || 'missing-id'}`,
  }) ?? {};

  const detailsLink = useMemo(() => onPressDetails ?? detailsPostLink, [onPressDetails, detailsPostLink]);
  const showDetailsShadow = useMemo(() => !!isPreview && !!post.content && post.content.length > 700, [isPreview, post.content]);

  const detailsShadowProps = useMemo(() => showDetailsShadow ? {
    shadowOpacity: 0.3,
    shadowOffset: { width: -5, height: -5 },
    shadowRadius: 10
  } : {}, [showDetailsShadow]);

  const author = post.author;
  const isAuthor = author && author.userId === currentUser?.id;
  const showEdit = isAuthor && !isPreview && post.id;

  const [loadingReplies, setLoadingReplies] = useState(false);
  useEffect(() => {
    if (loadingReplies && (post.replyCount == 0 || post.replies.length > 0)) {
      setLoadingReplies(false);
    }
  }, [loadingReplies, post.replyCount, post.replies.length]);
  const toggleReplies = useCallback((e: GestureResponderEvent) => {
    e.stopPropagation();
    // setTimeout(() => {
    requestAnimationFrame(() => {
      if (!loadingReplies && post.replies.length == 0) {
        setLoadingReplies(true);
        if (onLoadReplies) {
          onLoadReplies();
        }
        dispatch(loadPostReplies({ ...accountOrServer, postIdPath: replyPostIdPath! }));
      } else if (toggleCollapseReplies) {
        toggleCollapseReplies();
      }
    });
    // }, 1);
  }, [accountOrServer, loadingReplies, replyPostIdPath, post.replies.length, onLoadReplies, toggleCollapseReplies, dispatch]);
  const cannotToggleReplies = useMemo(() => !replyPostIdPath || post.replyCount == 0
    || (post.replies.length > 0 && !toggleCollapseReplies), [replyPostIdPath, post.replyCount, post.replies.length, toggleCollapseReplies]);

  const collapsed = useMemo(() => collapseReplies || post.replies?.length == 0, [collapseReplies, post.replies?.length]);

  // const embedSupported = post.embedLink && post.link && post.link.length;
  // let embedComponent: React.ReactNode | undefined = undefined;
  // if (embedSupported) {
  //   const url = new URL(post.link!);
  //   const hostname = url.hostname.split(':')[0]!;
  //   if (hostname.endsWith('twitter.com')) {
  //     embedComponent = <TwitterEmbed url={post.link!} />;
  //   } else if (hostname.endsWith('instagram.com')) {
  //     embedComponent = <InstagramEmbed url={post.link!} />;
  //   } else if (hostname.endsWith('facebook.com')) {
  //     embedComponent = <FacebookEmbed url={post.link!} />;
  //   } else if (hostname.endsWith('youtube.com')) {
  //     embedComponent = <YouTubeEmbed url={post.link!} />;
  //   } else if (hostname.endsWith('tiktok.com')) {
  //     embedComponent = <TikTokEmbed url={post.link!} />;
  //   } else if (hostname.endsWith('pinterest.com')) {
  //     embedComponent = <PinterestEmbed url={post.link!} />;
  //   } else if (hostname.endsWith('linkedin.com')) {
  //     embedComponent = <LinkedInEmbed url={post.link!} />;
  //   }
  // }

  const imagePreview = media?.find(isImageMedia);
  const showScrollableMediaPreviews = (media?.filter(m => !m.generated).length ?? 0) >= 2;
  // const singleMediaPreview = showScrollableMediaPreviews
  //   ? undefined
  //   : post?.media?.find(m => m.contentType.startsWith('image') && (!m.generated /*|| !isPreview*/));
  const previewUrl = useMediaUrl(imagePreview, accountOrServer);

  const showBackgroundPreview = !!imagePreview;// && hasBeenVisible;


  const componentKey = useComponentKey('post-card');
  const backgroundSize = document.getElementById(componentKey)?.clientWidth ?? postBackgroundSize(mediaQuery);
  const foregroundSize = backgroundSize * 0.7;

  const contentArea = <YStack overflow='hidden'
    maxHeight={isPreview
      ? (showScrollableMediaPreviews) ? 150 : 300
      : editing && !previewingEdits
        ? backgroundSize * (media.length > 0 ? 0.6 : 0.8)
        : undefined}
  >
    {
      editing && !previewingEdits
        ? <TextArea f={1} pt='$2' value={editedContent}
          disabled={savingEdits} opacity={savingEdits || editedContent == '' ? 0.5 : 1}
          h={(editedContent?.length ?? 0) > 300 ? window.innerHeight - 100 : undefined}
          onChangeText={setEditedContent}
          placeholder={`Text content (optional). Markdown is supported.`} />
        : content && content != ''
          ? <TamaguiMarkdown text={content} disableLinks={isPreview} />
          : undefined
    }
  </YStack>;

  const title = post.title && post.title != '' ? post.title : `Untitled Post ${post.id}`;
  const deleteDialog = <Dialog>
    <Dialog.Trigger asChild>
      <Button my='auto' size='$2' icon={Delete} disabled={deleting} transparent>
        Delete
      </Button>
    </Dialog.Trigger>
    <Dialog.Portal zi={100000000011}>
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
          <Dialog.Title>Delete {post.replyToPostId ? 'Reply' : 'Post'}</Dialog.Title>
          <Dialog.Description>
            Really delete {post.replyToPostId ? 'reply' : 'post'}?
            The content{post.replyToPostId ? '' : ' and title'} will be deleted, and your user account de-associated, but any replies (including quotes) will still be present.
          </Dialog.Description>

          <XStack gap="$3" jc="flex-end">
            <Dialog.Close asChild>
              <Button>Cancel</Button>
            </Dialog.Close>
            <Theme inverse>
              <Button onPress={doDeletePost}>Delete</Button>
            </Theme>
          </XStack>
        </YStack>
      </Dialog.Content>
    </Dialog.Portal>
  </Dialog>;

  const shrinkPreviews = !!isPreview && (
    !!forceShrinkPreview || (
      appShrinkPreviews && !forceExpandPreview
    )
  );
  const linkToDetails = isPreview || onPress;
  const conditionalDetailsLink = linkToDetails ? { ...detailsLink, cursor: 'pointer' } : {};
  // const conditionalDetailsLink = isPreview || onPress ? detailsLink : {};
  // console.log('postCard shrinkPreviews', shrinkPreviews, forceShrinkPreview, appShrinkPreviews, forceExpandPreview, isPreview, post.id);
  return (
    <AccountOrServerContextProvider value={accountOrServer}>
      <YStack w='100%' ref={ref!}>
        <AnimatePresence>
          {previewParent && post.replyToPostId
            ? <XStack w='100%' animation='standard' {...standardAnimation}>
              {mediaQuery.gtXs ? <Heading size='$5' ml='$3' mr='$0' marginVertical='auto' ta='center'>RE</Heading> : undefined}
              <XStack marginVertical='auto' marginHorizontal='$1'><ChevronRight /></XStack>

              <AnimatePresence>
                <Card f={1} theme="dark" size="$1" bordered={false} id={componentKey}
                  margin='$0'
                  backgroundColor={selectedPostId == previewParent.id ? '$backgroundFocus' : undefined}
                  // marginBottom={replyPostIdPath ? '$0' : '$3'}
                  // marginTop={replyPostIdPath ? '$0' : '$3'}
                  // padding='$2'
                  px='$2'
                  py='$1'
                  mb='$1'
                  // f={isPreview ? undefined : 1}
                  animation='standard' {...reverseStandardAnimation}
                  scale={0.92}
                  opacity={1}
                  y={0}
                  // enterStyle={{ y: -50, opacity: 0, }}
                  // exitStyle={{ opacity: 0, }}
                  pressStyle={{ scale: 0.91 }}
                  onPress={onPressParentPreview}
                >
                  <Card.Footer p={0}>
                    <YStack w='100%'>
                      <XStack mah={200} w='100%'>
                        <TamaguiMarkdown text={previewParent.content} shrink />
                      </XStack>

                      <XStack ml='auto' mr='$2'>
                        <AuthorInfo post={previewParent!} disableLink={false} shrink />
                      </XStack>
                    </YStack>
                  </Card.Footer>
                </Card>
              </AnimatePresence>
            </XStack>
            : undefined}
        </AnimatePresence>
        {/* <Theme inverse={selectedPostId == post.id}> */}
        <Card size="$4"
          bordered={!post.replyToPostId}
          // theme="dark"

          borderColor={showServerInfo && !post.replyToPostId ? primaryColor : undefined}
          margin='$1'
          backgroundColor={selectedPostId == post.id ? '$backgroundFocus' : undefined}
          marginBottom={replyPostIdPath ? '$0' : '$3'}
          marginTop={replyPostIdPath ? '$0' : '$3'}
          // marginRight={-10}
          f={isPreview ? undefined : 1}
          animation='standard'
          // pressStyle={isPreview ? { scale: 0.990 } : {}}
          scale={1}
          opacity={1}
          // w='100%'
          y={0}
        // enterStyle={{ y: -50, opacity: 0, }}
        // exitStyle={{ opacity: 0, }}
        // {...postLinkProps}
        >
          {!isReply && (post.link || post.title)
            ? <Card.Header /*pb={shrinkPreviews ? '$2' : undefined}*/ pb={0}>
              <XStack ai='center'>
                <StarButton post={post} />
                <YStack f={1}>
                  {linkToDetails
                    ? <Anchor textDecorationLine='none'
                      {...conditionalDetailsLink}
                    >
                      <YStack w='100%'>
                        <Heading size="$7" marginRight='auto'>
                          {title}
                        </Heading>
                      </YStack>
                    </Anchor>
                    : <YStack w='100%'>
                      <Heading size="$7" marginRight='auto'>
                        {title}
                      </Heading>
                    </YStack>}

                  {postLinkView}
                </YStack>

                {showServerInfo
                  ? <XStack my='auto'
                    w={shrinkServerInfo ? '$4' : undefined}
                    h={shrinkServerInfo ? '$4' : undefined}
                    jc={shrinkServerInfo ? 'center' : undefined}>
                    <ServerNameAndLogo server={server} shrinkToSquare={shrinkServerInfo} disableTooltip />
                  </XStack>
                  : undefined}
              </XStack>
            </Card.Header>
            : undefined}
          <Card.Footer p={0} >
            {deleted
              ? <Paragraph size='$1'>This {post.replyToPostId ? 'comment' : 'post'} has been deleted.</Paragraph>
              : <YStack zi={1000} w='100%'>
                <XStack ai='flex-start' w='100%' {...isReply ? { pl: '$2', pr: '$3' } : {}}>
                  <YStack f={1}>
                    {isReply ? <XStack mt='$1' pt='$1'><AuthorInfo {...{ post }} nameOnly /></XStack> : undefined}
                    <AnimatePresence>
                      {shrinkPreviews ? undefined : <YStack key='content' animation='standard' {...reverseStandardAnimation}>
                        <YStack mah={isPreview ? window.innerHeight - 50 : undefined} overflow='hidden'>
                          {editing && !previewingEdits
                            ? <PostMediaManager
                              link={post.link}
                              media={editedMedia}
                              setMedia={setEditedMedia}
                              embedLink={editedEmbedLink}
                              setEmbedLink={setEditedEmbedLink}
                              disableInputs={savingEdits}
                            />
                            : <PostMediaRenderer
                              groupContext={selectedGroup}
                              isVisible={isVisible || !isPreview}
                              post={{ ...post, media, embedLink }}
                              {...{ isPreview }} />}
                        </YStack>
                        <YStack {...isReply ? {} : { pl: '$3', pr: '$3' }}>
                          {linkToDetails
                            ? <Anchor textDecorationLine='none' {...conditionalDetailsLink}>
                              {contentArea}
                            </Anchor>
                            : contentArea}
                        </YStack>
                      </YStack>}
                    </AnimatePresence>
                  </YStack>
                </XStack>
                <AnimatePresence>
                  {shrinkPreviews ? undefined
                    : <YStack animation='standard' {...standardAnimation}>
                      <XStack key='edit-buttons' px='$3' flexWrap="wrap" ai='center'
                        // py={!showEdit && !isAuthor ? 0 : '$2'}
                        flexDirection="row-reverse"
                      >
                        <XStack gap='$2' flexWrap="wrap" ml='auto' maw='100%'>
                          {post.replyToPostId && !editing && post.visibility === Visibility.GLOBAL_PUBLIC
                            ? undefined
                            : <XStack key='visibility-edit' my='auto' ml='auto' py='$2' pl='$2'>
                              <VisibilityPicker
                                id={`visibility-picker-${post.id}${isPreview ? '-preview' : ''}`}
                                label='Post Visibility'
                                visibility={visibility}
                                onChange={setEditedVisibility}
                                visibilityDescription={v => postVisibilityDescription(v, selectedGroup, server)}
                                readOnly={!editing || previewingEdits}
                              />
                            </XStack>}
                          <XStack key='shareable-edit' my='auto' ml='auto' pb='$1'>
                            <ShareableToggle value={shareable}
                              setter={setEditedShareable}
                              isOwner={isAuthor}
                              readOnly={!editing || previewingEdits} />
                          </XStack>
                          {!post?.replyToPostId
                            ? <XStack maw='100%' mr={0} my='auto' ml='auto'>
                              <GroupPostManager post={federatedEntity(post, server)} isVisible={isVisible} />
                            </XStack>
                            : undefined}

                        </XStack>
                        <XStack py={showEdit ? '$2' : undefined} gap='$2' mr='auto'>
                          {showEdit
                            ? editing
                              ? <>
                                <Button my='auto' key='save' size='$2' icon={Save} onPress={saveEdits} color={primaryAnchorColor} disabled={savingEdits} transparent>
                                  Save
                                </Button>
                                <Button my='auto' key='cancel' size='$2' icon={XIcon} onPress={() => setEditing(false)} disabled={savingEdits} transparent>
                                  Cancel
                                </Button>
                                {previewingEdits
                                  ? <Button my='auto' key='preview-edit' size='$2' icon={Edit} onPress={() => setPreviewingEdits(false)} color={navAnchorColor} disabled={savingEdits} transparent>
                                    Edit
                                  </Button>
                                  :
                                  <Button my='auto' key='preview' size='$2' icon={Eye} onPress={() => setPreviewingEdits(true)} color={navAnchorColor} disabled={savingEdits} transparent>
                                    Preview
                                  </Button>}
                              </>
                              : <>
                                <Button my='auto' key='edit' size='$2' icon={Edit} onPress={() => setEditing(true)} disabled={deleting} transparent>
                                  Edit
                                </Button>

                                {deleteDialog}
                              </>
                            : isAuthor && post.id ? <XStack o={0.5}>{deleteDialog}</XStack> : undefined}
                        </XStack>
                      </XStack>
                    </YStack>}
                </AnimatePresence>
                <XStack w='100%' ai='center' p='$3' /*mt={showEdit ? -11 : -15}*/
                  mt={shrinkPreviews && isReply ? '$1' : undefined}
                  pt={isReply ? 10 : 0} {...detailsShadowProps}>
                  <XStack f={1}>
                    <AuthorInfo {...{ post }} dateOnly={isReply} />
                  </XStack>
                  {isReply ? <StarButton post={post} horizontal /> : undefined}
                  {onPressReply
                    ? <Button onPress={onPressReply} circular icon={Reply}
                      my='auto' size='$2' mr='$2' />
                    : undefined}
                  {showPermalink || (isReply && !isSubjectPost)
                    ? <Button circular icon={Link2} {...detailsPostLink}
                      my='auto' size='$2' mr='$2' />
                    : undefined}
                  <Anchor textDecorationLine='none' {...conditionalDetailsLink}>
                    <YStack h='100%' mr='$1'>
                      <Button opacity={isPreview ? 1 : 0.9} transparent={isPreview || !post?.replyToPostId || post.replyCount == 0}
                        borderColor={isPreview || cannotToggleReplies ? 'transparent' : undefined}
                        disabled={cannotToggleReplies || loadingReplies}
                        marginVertical='auto'
                        // mr={isPreview ? '$2' : undefined}
                        size='$3'
                        onPress={toggleReplies} paddingRight={cannotToggleReplies || isPreview ? '$2' : '$0'} paddingLeft='$2'>
                        <XStack opacity={0.9}>
                          <YStack marginVertical='auto' scale={0.75}>
                            {!post.replyToPostId ? <Paragraph size="$1" ta='right'>
                              {post.responseCount} comment{post.responseCount == 1 ? '' : 's'}
                            </Paragraph> : undefined}
                            {(post.replyToPostId) && (post.responseCount != post.replyCount) ? <Paragraph size="$1" ta='right'>
                              {post.responseCount} response{post.responseCount == 1 ? '' : 's'}
                            </Paragraph> : undefined}
                            {isPreview || post.replyCount == 0 ? undefined : <Paragraph size="$1" ta='right'>
                              {post.replyCount} repl{post.replyCount == 1 ? 'y' : 'ies'}
                            </Paragraph>}
                          </YStack>
                          {!cannotToggleReplies ? <XStack marginVertical='auto'
                            animation='standard'
                            rotate={collapsed ? '0deg' : '90deg'}
                          >
                            <ChevronRight opacity={loadingReplies ? 0.5 : 1} />
                          </XStack> : undefined}
                        </XStack>
                      </Button>
                    </YStack>
                  </Anchor>
                </XStack>
              </YStack>
            }
          </Card.Footer>
          {imagePostBackgrounds ?
            <Card.Background>
              {(showBackgroundPreview) ?
                <FadeInView>
                  <Image
                    pos="absolute"
                    width={backgroundSize}
                    opacity={fancyPostBackgrounds ? 0.11 : 0.04}
                    height={backgroundSize}
                    resizeMode="cover"
                    als="flex-start"
                    source={{ uri: previewUrl!, height: backgroundSize, width: backgroundSize }}
                    blurRadius={fancyPostBackgrounds ? 1.5 : undefined}
                    // borderRadius={5}
                    borderBottomRightRadius={5}
                  />
                </FadeInView>
                : undefined}
            </Card.Background>
            : undefined}
        </Card >
        {/* </Theme> */}
      </YStack >
    </AccountOrServerContextProvider>
  );
};

export default PostCard;
