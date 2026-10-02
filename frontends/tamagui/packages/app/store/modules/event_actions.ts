import { Event, Rsvps, Occasion, EventListingType, GetRsvpsRequest, GetEventsRequest, GetEventsResponse, TimeFilter } from "@rellm/api";
import {
  AsyncThunk,
  createAsyncThunk
} from "@reduxjs/toolkit";
import { AccountOrServer, getCredentialClient } from "..";
import { HasIdFromServer } from "../federation";

// `Event`/`Occasion` no longer carry their own surrogate `id` -- each one's identity *is* its
// own `post.id`. The Redux store's federation machinery (`FederatedEntity<T>`/`federatedId`/etc.,
// see `../federation.ts`) is generic over `T extends HasIdFromServer` (`{ id: string }`) and reads
// `.id` directly at runtime, so every `Event`/`Occasion` gets a synthetic top-level `id`
// stamped on here, at the API boundary, copied from its own `post.id` -- once stamped, the rest of
// the store (and any code reading a `FederatedEvent`/`FederatedOccasion` out of it) can keep
// treating `.id` as a normal field, same as any other entity (User, Post, Group, etc.).
export type IdentifiedOccasion = Occasion & HasIdFromServer;
export type IdentifiedEvent = Omit<Event, "occasions"> & HasIdFromServer & { occasions: IdentifiedOccasion[] };
export type IdentifiedGetEventsResponse = Omit<GetEventsResponse, "events"> & { events: IdentifiedEvent[] };

export function identifyOccasion(occasion: Occasion): IdentifiedOccasion {
  return { ...occasion, id: occasion.post!.id };
}
export function identifyEvent(event: Event): IdentifiedEvent {
  return { ...event, id: event.post!.id, occasions: event.occasions.map(identifyOccasion) };
}
export function identifyGetEventsResponse(response: GetEventsResponse): IdentifiedGetEventsResponse {
  return { ...response, events: response.events.map(identifyEvent) };
}

export type CreateEvent = AccountOrServer & Event;
export const createEvent: AsyncThunk<IdentifiedEvent, CreateEvent, any> = createAsyncThunk<IdentifiedEvent, CreateEvent>(
  "events/create",
  async (request) => {
    const client = await getCredentialClient(request);
    return identifyEvent(await client.createEvent(request, client.credential));
  }
);

export type UpdateEvent = AccountOrServer & Event;
export const updateEvent: AsyncThunk<IdentifiedEvent, CreateEvent, any> = createAsyncThunk<IdentifiedEvent, UpdateEvent>(
  "events/update",
  async (request) => {
    const client = await getCredentialClient(request);
    return identifyEvent(await client.updateEvent(request, client.credential));
  }
);

export type DeleteEvent = AccountOrServer & Event;
export const deleteEvent: AsyncThunk<IdentifiedEvent, CreateEvent, any> = createAsyncThunk<IdentifiedEvent, DeleteEvent>(
  "events/delete",
  async (request) => {
    const client = await getCredentialClient(request);
    return identifyEvent(await client.deleteEvent(request, client.credential));
  }
);

export type LoadEventsRequest = AccountOrServer & {
  listingType?: EventListingType,
  page?: number
  filter?: TimeFilter
  force?: boolean
};
export const defaultEventListingType = EventListingType.ALL_ACCESSIBLE_EVENTS;
export const loadEventsPage: AsyncThunk<IdentifiedGetEventsResponse, LoadEventsRequest, any> = createAsyncThunk<IdentifiedGetEventsResponse, LoadEventsRequest>(
  "events/loadPage",
  async (request) => {
    let client = await getCredentialClient(request);
    let response = await client.getEvents({
      ...request,
      listingType: request.listingType ?? defaultEventListingType,
      timeFilter: request.filter
    }, client.credential);
    // console.log('loadEventsPage', request.server?.host, response);
    return identifyGetEventsResponse(response);
  },
  // {
  //   condition: (request, { getState }) => {
  //     const state = getState() as EventsState;
  //     return request.force || getFederated(state.pagesStatus, request) !== "loading";
  //   }
  // }
);

export type LoadEvent = { id?: string, postId?: string, occasionId?: string } & AccountOrServer;
export const loadEvent: AsyncThunk<IdentifiedEvent, LoadEvent, any> = createAsyncThunk<IdentifiedEvent, LoadEvent>(
  "events/loadOne",
  async (request) => {
    const client = await getCredentialClient(request);
    // `event_id`/`occasion_id` were removed from `GetEventsRequest` -- `post_id` is a
    // strict superset (looks up by the Event's own Post ID *or* any of its Occasions' Post
    // ID), so any of `id`/`postId`/`occasionId` (all historically post ids under the hood) works.
    const response = await client.getEvents(GetEventsRequest.create({
      postId: request.id ?? request.postId ?? request.occasionId
    }), client.credential);
    if (response.events.length == 0) throw 'Event not found';
    const event = response.events[0]!;
    return identifyEvent(event);
  }
);

export type LoadRsvpData = GetRsvpsRequest & AccountOrServer;
export const loadRsvpData: AsyncThunk<Rsvps, LoadRsvpData, any> = createAsyncThunk<Rsvps, LoadRsvpData>(
  "events/loadRsvpData",
  async (request) => {
    const client = await getCredentialClient(request);

    const eventRsvpsResponse = await client.getRsvps({
      occasionId: request.occasionId,
      anonymousAttendeeAuthToken: request.anonymousAttendeeAuthToken
    }, client.credential);

    return eventRsvpsResponse;
  }
);
