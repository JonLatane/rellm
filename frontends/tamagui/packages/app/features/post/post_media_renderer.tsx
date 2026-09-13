import { FederatedGroup, federateId, useServerTheme } from "app/store";
import React, { useEffect, useMemo, useState } from "react";

import { Post } from "@rellm/api";
import { Anchor, ScrollView, Spinner, XStack, YStack, useMedia } from '@rellm/ui';
import { useCurrentServer, useMediaUrl, usePostDispatch } from "app/hooks";
import { FacebookEmbed, InstagramEmbed, LinkedInEmbed, PinterestEmbed, TikTokEmbed, XEmbed, YouTubeEmbed } from 'react-social-media-embed';
import { useLink } from "solito/link";

import { FadeInView } from 'app/components';
import { isImageMedia } from "app/utils";
import { MediaRenderer } from "../media/media_renderer";
import { postBackgroundSize } from "./post_card";

export interface PostMediaRendererProps {
  post: Post;
  isPreview?: boolean;
  groupContext?: FederatedGroup;
  smallPreview?: boolean;
  xsPreview?: boolean;
  detailsLink?: LinkProps;
  renderGeneratedMedia?: boolean;
  isVisible?: boolean;
}

export type LinkProps = {
  accessibilityRole: "link";
  onPress: (e?: any) => void;
  href: string;
}

export const PostMediaRenderer: React.FC<PostMediaRendererProps> = ({
  post,
  isPreview,
  groupContext,
  smallPreview,
  xsPreview,
  detailsLink: parentDetailsLink,
  renderGeneratedMedia,
  isVisible = true,
}) => {
  const { dispatch, accountOrServer } = usePostDispatch(post);
  const mediaQuery = useMedia();
  const { primaryColor, navColor } = useServerTheme(accountOrServer.server);

  const currentServer = useCurrentServer();
  const isPrimaryServer = useMemo(() => !!currentServer &&
    currentServer?.host === accountOrServer.server?.host, [currentServer, accountOrServer.server?.host]);
  const isGroupPrimaryServer = useMemo(() => !!currentServer &&
    currentServer?.host === groupContext?.serverHost, [currentServer, groupContext?.serverHost]);

  const detailsLinkId = useMemo(() => !isPrimaryServer
    ? federateId(post.id, accountOrServer.server)
    : post.id, [isPrimaryServer, post.id, accountOrServer.server]);
  const detailsGroupShortname = useMemo(() => groupContext
    ? (!isGroupPrimaryServer
      ? federateId(groupContext.shortname, accountOrServer.server)
      : groupContext.shortname)
    : undefined, [groupContext, isGroupPrimaryServer, accountOrServer.server]);
  const postDetailsLink = useLink({
    href: groupContext
      ? `/g/${detailsGroupShortname}/p/${detailsLinkId}`
      : `/post/${detailsLinkId}`,
  });
  const detailsLink: LinkProps = useMemo(() => parentDetailsLink ?? postDetailsLink, [parentDetailsLink, postDetailsLink]);

  const embedSupported = useMemo(() => post.embedLink && post.link && post.link.length, [post.embedLink, post.link]);
  const embedComponent = useMemo(() => {
    let embed: React.ReactNode | undefined = undefined;
    if (embedSupported) {
      const url = new URL(post.link!);
      const hostname = url.hostname.split(':')[0]!;
      if (hostname.endsWith('twitter.com') || hostname.endsWith('t.co') || hostname.endsWith('x.com')) {
        embed = <XEmbed url={post.link!} />;
      } else if (hostname.endsWith('instagram.com')) {
        embed = <InstagramEmbed width='100%' url={post.link!} />;
      } else if (hostname.endsWith('facebook.com')) {
        embed = <FacebookEmbed width='100%' url={post.link!} />;
      } else if (hostname.endsWith('youtube.com')) {
        embed = <YouTubeEmbed width='100%' url={post.link!} />;
      } else if (hostname.endsWith('tiktok.com')) {
        embed = <TikTokEmbed width='100%' url={post.link!} />;
      } else if (hostname.endsWith('pinterest.com')) {
        embed = <PinterestEmbed width='100%' url={post.link!} />;
      } else if (hostname.endsWith('linkedin.com')) {
        embed = <LinkedInEmbed width='100%' url={post.link!} />;
      }
    }
    embed = embed
      ? <YStack mx='auto' width='100%' ai='center'>{embed}</YStack>
      : undefined;

    return embed;
  }, [embedSupported, post.link]);

  const generatedPreview = useMemo(() => post?.media?.find(m => isImageMedia(m) && m.generated), [post?.media]);
  const hasGeneratedPreview = useMemo(() => generatedPreview && post?.media?.length == 1 && !embedComponent, [generatedPreview, post?.media?.length, embedComponent]);

  const scrollableMediaMinCount = useMemo(() => isPreview && hasGeneratedPreview ? 3 : 2, [isPreview, hasGeneratedPreview]);
  const showScrollableMediaPreviews = useMemo(() => (post?.media?.length ?? 0) >= scrollableMediaMinCount, [post?.media?.length, scrollableMediaMinCount]);
  const singleMediaPreview = useMemo(() => showScrollableMediaPreviews
    ? undefined
    : post?.media?.find(m => !m.generated || renderGeneratedMedia), [showScrollableMediaPreviews, post?.media, renderGeneratedMedia]);
  // const singleMediaPreviewUrl = useMediaUrl(singleMediaPreview?.id);
  // const backgroundImageUrl = useMediaUrl(hasGeneratedPreview ? generatedPreview?.id : undefined);

  // const isReply = post.replyToPostId != null;
  // const backgroundSize = postBackgroundSize(mediaQuery);
  // const foregroundSize = backgroundSize * 0.7;

  // const singlePreviewSize = xsPreview ? 150 : smallPreview ? 300 : foregroundSize;
  // console.log('PostMediaRenderer', { singleMediaPreview, showScrollableMediaPreviews, media: post.media })

  const [hasBeenVisible, setHasBeenVisible] = useState(isVisible);
  useEffect(() => { if (isVisible && !hasBeenVisible) setHasBeenVisible(true) }, [isVisible]);

  return <YStack zi={1000} width='100%' ai='center'>

    {embedComponent
      ? hasBeenVisible
        ? embedComponent
        : <XStack h='$10' />
      : undefined}

    {showScrollableMediaPreviews ?
      <XStack w='100%' maw={800}>
        <ScrollView horizontal w={isPreview ? '260px' : '100%'}
          h={mediaQuery.gtXs ? '400px' : '260px'} >
          <XStack gap='$2'>
            {post.media.map((mediaRef, i) => {
              // debugger;
              return <YStack key={mediaRef.id} w={mediaQuery.gtXs ? '400px' : '260px'} h='100%'>
                <MediaRenderer media={mediaRef} isPreview={isPreview} />
              </YStack>;
            })}
          </XStack>
        </ScrollView>
      </XStack> : undefined}

    <Anchor w='100%' textDecorationLine='none' {...{ ...(isPreview && singleMediaPreview && isImageMedia(singleMediaPreview) ? detailsLink : {}) }}>
      <YStack w='100%'>
        {singleMediaPreview
          ?
          <YStack key={singleMediaPreview.id} w='100%' /*maw='100%' mah='100%' h={isPreview ? singlePreviewSize : undefined}*/ mx='auto'>
            <MediaRenderer media={singleMediaPreview} />
          </YStack>
          : undefined}
      </YStack>
    </Anchor>
  </YStack>;
};
