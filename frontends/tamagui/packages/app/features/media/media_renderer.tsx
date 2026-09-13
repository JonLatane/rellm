import { useProvidedDispatch } from "app/hooks";
import { RellmServer, useServerTheme } from "app/store";
import React, { useMemo } from 'react';

import { Anchor, Paragraph, Text, YStack, useMedia } from "@rellm/ui";
import { MediaRef } from "app/contexts";
import { getOriginalContentType } from "app/utils";
import ReactPlayer from 'react-player/lazy';
import { useMediaUrl } from '../../hooks/use_media_url';
import { FadeInView } from "../post";

interface Props {
  media: MediaRef;
  failQuietly?: boolean;
  serverOverride?: RellmServer;
  forceImage?: boolean;
  isVisible?: boolean;
  isPreview?: boolean;
}

// MediaRenderers will always be styled with width=100% and height=100%.
// Use them accordingly.
export const MediaRenderer: React.FC<Props> = ({
  media,
  failQuietly = false,
  serverOverride,
  forceImage = false,
  isPreview = false
}) => {
  const { dispatch, accountOrServer } = useProvidedDispatch(serverOverride);
  const server = accountOrServer.server;
  const { navAnchorColor } = useServerTheme(server);
  const mediaQuery = useMedia();

  const ReactPlayerShim = ReactPlayer as any;

  const mediaUrl = useMediaUrl(media, { server });
  const contentType = getOriginalContentType(media);
  const [type, subType] = useMemo(() => {
    let [type, subType] = contentType.split('/');
    if (forceImage) {
      type = 'image';
    }
    return [type, subType];
  }, [contentType, forceImage]);

  const renderContent = useMemo(() => {
    if (!server) return <></>;

    // let view: React.JSX.Element;
    switch (type) {
      case 'image':
        return <FadeInView w='100%' h='100%'>
          <img style={{ width: '100%', height: '100%', objectFit: 'contain' }}
            src={mediaUrl} />
        </FadeInView>;
      case 'video':
        return <FadeInView w='100%' h='100%'>
          <YStack w='100%' h='100%' ac='center' jc='center' mah={isPreview ? 500 : undefined}>
            <ReactPlayerShim width='100%'
              height='100%'
              // height={isPreview ? mediaQuery.gtXs ? '500px' : '300px' : '100%'}
              url={mediaUrl} controls />
          </YStack>
        </FadeInView>;
      default:
        // If all else fails, render it as an HTML object and rely on the tag's standard fallback.
        return <FadeInView w='100%' h='100%'>
          <object style={{ width: '100%', height: '100%', backgroundColor: 'white' }} data={mediaUrl} type={contentType} width="100%" height={mediaQuery.gtXs ? '500px' : '350px'}>
            {failQuietly ? undefined : <YStack p='$3'>
              <Paragraph size='$2' color={'black'}>
                Media rendering is not supported in your browser for type <Text fontFamily='$mono' color={'black'}>{contentType}</Text>. <Anchor href={mediaUrl} color={navAnchorColor}>Download it instead.</Anchor>
              </Paragraph>
            </YStack>}
          </object>
        </FadeInView>;
    }
  }, [server, type, mediaUrl, isPreview, mediaQuery.gtXs, failQuietly, contentType, navAnchorColor]);

  return renderContent;
};
