import { Event, Rsvps, Occasion, EventListingType, TimeFilter } from "@rellm/api";
import {
  Dictionary,
  EntityAdapter,
  EntityId, PayloadAction,
  createEntityAdapter,
  createSlice
} from "@reduxjs/toolkit";
import moment from "moment";
import { Federated, FederatedEntity, HasServer, createFederated, federateId, federatedEntities, federatedId, federatedPayload, getFederated, parseFederatedId, setFederated } from '../federation';
import { FederatedPagesStatus, PaginatedIds, createFederatedPagesStatus } from "../pagination";
import { createEvent, defaultEventListingType, deleteEvent, IdentifiedEvent, IdentifiedOccasion, loadEvent, loadEventsPage, loadRsvpData, updateEvent } from './event_actions';
import { loadGroupEventsPage } from "./group_actions";
import { loadUserEvents } from "./user_actions";
export * from './event_actions';

export type FederatedEvent = FederatedEntity<IdentifiedEvent>;
export type FederatedOccasion = FederatedEntity<IdentifiedOccasion>;
export interface EventsState {
  pagesStatus: FederatedPagesStatus;
  ids: EntityId[];
  entities: Dictionary<FederatedEvent>;
  // Links occasion IDs to Event IDs.
  occasionEvents: Dictionary<string>;
  // occasions: Dictionary<Occasion>;
  occasionPages: Federated<GroupedOccasionPages>;
  failedEventIds: string[];
  failedOccasionIds: string[];
  failedPostIds: string[];
  // Maps Post IDs to Event IDs.
  postEvents: Dictionary<string>;
  // Maps Post IDs to Occasion IDs.
  postOccasions: Dictionary<string>;
  upcomingEventsTime: string;
  upcomingEventsTimeFilter?: TimeFilter;
  // Maps Occasion IDs to RSVP data.
  rsvpData: Dictionary<Rsvps>;
}

// Stores pages of listed event *occasions* for listing types used in the UI.
// i.e.: eventPages[EventListingType.ALL_ACCESSIBLE_EVENTS]['{"ends_after":null}'][0]:  -> ["occasionId1", "occasionId2"].
// Events should be loaded from the adapter/slice's entities.
// Maps EventListingType -> serialized timeFilter-> page (as a number) -> occasionIds
export type GroupedOccasionPages = Dictionary<Dictionary<PaginatedIds>>
export const unfilteredTime = 'unfiltered';
export function serializeTimeFilter(filter: TimeFilter | undefined): string {
  if (!filter) return unfilteredTime;
  return JSON.stringify(TimeFilter.toJSON(filter ?? TimeFilter.create()));
};

export const eventsAdapter: EntityAdapter<FederatedEvent> = createEntityAdapter<FederatedEvent>({
  selectId: (event) => federatedId(event),
  sortComparer: (a, b) => moment.utc(b.post!.createdAt).unix() - moment.utc(a.post!.createdAt).unix(),
});

const initialState: EventsState = {
  pagesStatus: createFederatedPagesStatus(),
  failedEventIds: [],
  failedOccasionIds: [],
  failedPostIds: [],
  occasionPages: createFederated({}),
  occasionEvents: {},
  postEvents: {},
  postOccasions: {},
  upcomingEventsTime: moment(Date.now()).toISOString(true),
  rsvpData: {},
  ...eventsAdapter.getInitialState(),
};

export const eventsSlice = createSlice({
  name: "events",
  initialState: initialState,
  reducers: {
    upsertEvent: eventsAdapter.upsertOne,
    removeEvent: eventsAdapter.removeOne,
    resetEvents: (state, action: PayloadAction<{ serverHost: string | undefined }>) => {
      if (!action.payload.serverHost) return;

      const eventsIdsToRemove = state.ids
        .filter(id => parseFederatedId(id as string).serverHost === action.payload.serverHost);
      eventsAdapter.removeMany(state, eventsIdsToRemove);
      Object.keys(state.occasionEvents)
        .filter(id => parseFederatedId(id).serverHost === action.payload.serverHost)
        .forEach(id => delete state.occasionEvents[id]);
      Object.keys(state.postEvents)
        .filter(id => parseFederatedId(id).serverHost === action.payload.serverHost)
        .forEach(id => delete state.postEvents[id]);
      Object.keys(state.postOccasions)
        .filter(id => parseFederatedId(id).serverHost === action.payload.serverHost)
        .forEach(id => delete state.postOccasions[id]);
      state.failedEventIds = state.failedEventIds.filter(id => parseFederatedId(id).serverHost !== action.payload.serverHost);
      state.failedOccasionIds = state.failedOccasionIds.filter(id => parseFederatedId(id).serverHost !== action.payload.serverHost);
      delete state.occasionPages.values[action.payload.serverHost];
      delete state.pagesStatus.values[action.payload.serverHost];
    },
    setUpcomingEventsTimeFilter: (state, action: PayloadAction<{ timeFilter: TimeFilter }>) => {
      state.upcomingEventsTimeFilter = action.payload.timeFilter;
      // if (!state.upcomingEventsTimeFilter) {
      //   const pageLoadTime = moment(Date.now()).toISOString(true);
      //   const endsAfter = moment(pageLoadTime).subtract(1, "week").toISOString(true);
      //   const timeFilter: TimeFilter = { endsAfter: endsAfter ? toProtoISOString(endsAfter) : undefined };
      //   state.upcomingEventsTimeFilter = timeFilter;
      // }
      // return state.upcomingEventsTimeFilter;
    },
  },
  extraReducers: (builder) => {
    builder.addCase(createEvent.fulfilled, (state, action) => {
      const payload = federatedPayload(action);
      eventsAdapter.upsertOne(state, payload);
      const occasionIds = payload.occasions.map(occasion => federateId(occasion.id, action));
      state.occasionEvents = {
        ...state.occasionEvents,
        ...Object.fromEntries(
          occasionIds.map(occasionId => [occasionId, federateId(payload.id, action)])
        )
      };

      const pagesStatus = getFederated(state.pagesStatus, action);
      if (pagesStatus === 'loaded') {
        // Append the Events to ALL pages for any/all timefilters, etc.
        // This could be better done later, maybe. Refresh page data only without the
        // rest of the EventsState maybe?
        const occasionPages = getFederated(state.occasionPages, action);
        for (const listingTypeStr of Object.keys(occasionPages)) {
          const listingType = parseInt(listingTypeStr) as EventListingType;
          for (const filterStr of Object.keys(occasionPages[listingType]!)) {
            for (const pageStr of Object.keys(occasionPages[listingType]![filterStr]!)) {
              occasionPages[listingType]![filterStr]![pageStr]!.unshift(...occasionIds);
            }
          }
        }

        setFederated(state.occasionPages, action, occasionPages);
      }
    });
    builder.addCase(updateEvent.fulfilled, (state, action) => {
      const event = federatedPayload(action);
      mergeEvent(state, event, action);
      // setTimeout(() => {
      //   store.dispatch(loadEventsPage({ page: 0, listingType: defaultEventListingType, filter: undefined }));
      // }, 1);
    });
    builder.addCase(loadEventsPage.pending, (state, action) => {
      setFederated(state.pagesStatus, action, "loading");
    });
    builder.addCase(loadEventsPage.fulfilled, (state, action) => {
      setFederated(state.pagesStatus, action, "loaded");
      // console.log('loaded events page', action.payload.events.length);
      const events = federatedEntities(action.payload.events, action);
      events.forEach((e) => mergeEvent(state, e, action));

      const occasionIds = action.payload.events.flatMap(event => event.occasions.map(occasion => federateId(occasion.id, action)));

      const page = action.meta.arg.page || 0;
      const listingType = action.meta.arg.listingType ?? defaultEventListingType;
      const serializedFilter = serializeTimeFilter(action.meta.arg.filter);

      const serverEventPages = getFederated(state.occasionPages, action);
      if (!serverEventPages[listingType]) serverEventPages[listingType] = {};
      if (!serverEventPages[listingType]![serializedFilter] || page === 0) serverEventPages[listingType]![serializedFilter] = [];

      const eventPages: string[][] = serverEventPages[listingType]![serializedFilter]!;
      eventPages[page] = occasionIds;
      setFederated(state.occasionPages, action, serverEventPages);
    });
    builder.addCase(loadEventsPage.rejected, (state, action) => {
      setFederated(state.pagesStatus, action, "errored");
    });
    const saveSingleEvent = (state: EventsState, action: PayloadAction<IdentifiedEvent, any, any>) => {
      const event = federatedPayload(action);
      mergeEvent(state, event, action);
    };
    builder.addCase(loadEvent.fulfilled, saveSingleEvent);
    builder.addCase(loadEvent.rejected, (state, action) => {
      const { id: eventId, postId, occasionId } = action.meta.arg;
      if (eventId) {
        state.failedEventIds.push(federateId(eventId, action));
      }
      if (postId) {
        state.failedPostIds.push(federateId(postId, action));
      }
      if (occasionId) {
        state.failedOccasionIds.push(federateId(occasionId, action));
      }
    });

    builder.addCase(loadUserEvents.fulfilled, (state, action) => {
      const events = federatedEntities(action.payload.events, action);
      if (!events) return;

      events.forEach((e) => mergeEvent(state, e, action));
      // upsertEvents(state, events);
      events.forEach((e) => mergeEvent(state, e, action));
    });
    builder.addCase(loadGroupEventsPage.fulfilled, (state, action) => {
      const events = federatedEntities(action.payload.events, action);
      // upsertEvents(state, events);
      events.forEach((e) => mergeEvent(state, e, action));
    });
    builder.addCase(deleteEvent.fulfilled, (state, action) => {
      eventsAdapter.removeOne(state, federatedId(federatedPayload(action)));
    });
    builder.addCase(loadRsvpData.fulfilled, (state, action) => {
      const rsvpData = action.payload;
      const occasionId = federateId(action.meta.arg.occasionId, action);
      state.rsvpData[occasionId] = rsvpData;
    })
  },
});

const mergeEvent = (state: EventsState, event: FederatedEvent, action: HasServer) => {
  // console.log('merging event', event);
  const federatedEventId = federateId(event.id, action);
  const oldEvent = selectEventById(state, federatedId(event));
  if (event.post) {
    state.postEvents[federateId(event.post!.id, action)] = federatedEventId;
  }
  let occasions = event.occasions;
  occasions.forEach(occasion => {
    const federatedOccasionId = federateId(occasion.id, action);
    const federatedOccasionPostId = federateId(occasion.post!.id, action);
    state.occasionEvents[federatedOccasionId] = federatedEventId;
    state.postOccasions[federatedOccasionPostId] = federatedOccasionId;
  });
  if (oldEvent) {
    occasions = oldEvent.occasions.filter(oi => !occasions.find(ni => ni.id == oi.id)).concat(event.occasions);
  }
  event.occasions.sort((a, b) => moment.utc(a.startsAt).unix() - moment.utc(b.startsAt).unix());
  eventsAdapter.upsertOne(state, { ...event, occasions });
};

export const { removeEvent, resetEvents, setUpcomingEventsTimeFilter } = eventsSlice.actions;
export const { selectAll: selectAllEvents, selectById: selectEventById } = eventsAdapter.getSelectors();
export const eventsReducer = eventsSlice.reducer;
export const upsertEvent = eventsAdapter.upsertOne;
export const upsertEvents = eventsAdapter.upsertMany;
export default eventsReducer;
