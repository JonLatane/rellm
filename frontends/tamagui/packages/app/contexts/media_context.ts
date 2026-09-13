import { useDebounceValue } from "@rellm/ui";

import { useCreationServer } from "app/hooks";
import { MediaRef } from "app/utils";
import { createContext, useContext, useEffect, useState } from "react";

export type { MediaRef };

type MediaContextType = {
  mediaSheetOpen: boolean;
  setMediaSheetOpen: (v: boolean) => void;

  selectedMedia: MediaRef[];
  setSelectedMedia: (v: MediaRef[]) => void;

  isSelecting: boolean;
  setSelecting: (v: boolean) => void;

  isMultiselect: boolean;
  setMultiselect: (v: boolean) => void;

  contentTypePrefixFilter?: string;
  setContentTypePrefixFilter: (v: string) => void;

  // selectedGroup?: FederatedGroup;
  // sharingPostId?: string;
  // setSharingPostId: (postId: string | undefined) => void;
  // infoGroupId?: string;
  // setInfoGroupId: (groupId: string | undefined) => void;
};

export const MediaContext = createContext<MediaContextType>({
  mediaSheetOpen: false,
  setMediaSheetOpen: () => { console.warn('MediaContextProvider not set. Use useNewMediaContext at the top level of the app.') },

  selectedMedia: [],
  setSelectedMedia: () => { console.warn('MediaContextProvider not set. Use useNewMediaContext at the top level of the app.') },

  isSelecting: false,
  setSelecting: () => { console.warn('MediaContextProvider not set. Use useNewMediaContext at the top level of the app.') },

  isMultiselect: false,
  setMultiselect: () => { console.warn('MediaContextProvider not set. Use useNewMediaContext at the top level of the app.') },

  setContentTypePrefixFilter: () => { console.warn('MediaContextProvider not set. Use useNewMediaContext at the top level of the app.') },
});

export const MediaContextProvider = MediaContext.Provider;
export const MediaContextConsumer = MediaContext.Consumer;
export const useMediaContext = () => useContext(MediaContext);
export function useNewMediaContext(): MediaContextType {
  const { creationServer } = useCreationServer();
  const [mediaSheetOpen, setMediaSheetOpen] = useState(false);
  const [selectedMedia, setSelectedMedia] = useState<MediaRef[]>([]);

  useEffect(() => {
    setSelectedMedia([]);
  }, [creationServer]);

  const [isSelecting, setSelecting] = useState(false);
  const [isMultiselect, setMultiselect] = useState(false);
  const [contentTypePrefixFilter, setContentTypePrefixFilter] = useState(undefined as string | undefined);


  // const mediaSheetOpenDebounce = useDebounceValue(setMediaSheetOpen, 300);
  useEffect(() => {
    if (!mediaSheetOpen) {
      setSelectedMedia([]);
      setSelecting(false);
      setMultiselect(false);
      setContentTypePrefixFilter(undefined);
    }
  }, [mediaSheetOpen]);

  return {
    mediaSheetOpen,
    setMediaSheetOpen,
    selectedMedia,
    setSelectedMedia,
    isSelecting,
    setSelecting,
    isMultiselect,
    setMultiselect,
    contentTypePrefixFilter,
    setContentTypePrefixFilter,
  }
}