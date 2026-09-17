import { Follow, User } from "@rellm/api";
import {
  Dictionary,
  EntityAdapter,
  EntityId,
  PayloadAction,
  createEntityAdapter,
  createSlice
} from "@reduxjs/toolkit";
import { passes } from "app/utils/moderation_utils";
import moment from "moment";
import { AccountOrServer, FederatedPagesStatus, PaginatedIds, createEvent, createFederatedPagesStatus, createPost, defederateAccounts, federateAccounts, loadGroupMembers, notifyUserDeleted, store, upsertUserData } from "..";
import { Federated, FederatedAction, FederatedEntity, createFederated, federateId, federatedEntities, federatedEntity, federatedEntityId, federatedId, getFederated, parseFederatedId, setFederated } from '../federation';
import { LoadUser, LoadUsername, defaultUserListingType, deleteUser, followUnfollowUser, loadUser, loadUserEvents, loadUserPosts, loadUserReplies, loadUsername, loadUsersPage, respondToFollowRequest, updateUser } from "./user_actions";

// `hasAdvancedData` is client-only (no longer a wire field): it's set true when a user
// is upserted from a single-user lookup (`loadUser`/`loadUsername`/`updateUser`), which is
// the only case where the backend populates `federatedProfiles`. List-type fetches
// (`loadUsersPage`) don't set it, so a user cached from a list still knows it needs a
// real fetch before its `federatedProfiles` can be trusted.
export type FederatedUser = FederatedEntity<User> & { hasAdvancedData?: boolean };
export function federatedUsername(user: FederatedUser): string {
  return `${user.username}@${user.serverHost}`;
}

export interface UsersState {
  pagesStatus: FederatedPagesStatus;
  ids: EntityId[];
  entities: Dictionary<FederatedUser>;
  usernameIds: Federated<Dictionary<string>>;
  failedUsernames: Federated<string[]>;
  failedUserIds: string[];
  idPosts: Dictionary<string[]>;
  idReplies: Dictionary<string[]>;
  idOccasions: Dictionary<string[]>;
  // Stores pages of listed users for listing types used in the UI.
  // i.e.: userPages[PostListingType.ALL_ACCESSIBLE_POSTS][1] -> ["userId1", "userId2"].
  // Users should be loaded from the adapter/slice's entities.
  // Maps UserListingType -> page -> userIds
  userPages: Federated<Dictionary<PaginatedIds>>;
  mutatingUserIds: string[];
}


export interface UsersSlice {
  adapter: EntityAdapter<User>;
}

export const usersAdapter: EntityAdapter<FederatedUser> = createEntityAdapter<FederatedUser>({
  selectId: (user) => federatedId(user),
  sortComparer: (a, b) => moment.utc(b.createdAt).unix() - moment.utc(a.createdAt).unix(),
});

export function federateUserId(action: FederatedAction & PayloadAction<any, any, { arg: AccountOrServer & { userId: string } }>): string {
  return federateId(action.meta.arg.userId, action);
}

export const selectors = usersAdapter.getSelectors();

const initialState: UsersState = {
  pagesStatus: createFederatedPagesStatus(),
  usernameIds: createFederated({}),
  failedUsernames: createFederated([]),
  failedUserIds: [],
  idPosts: {},
  idReplies: {},
  idOccasions: {},
  userPages: createFederated({}),
  mutatingUserIds: [],
  ...usersAdapter.getInitialState(),
};

export const usersSlice = createSlice({
  name: "users",
  initialState: initialState,
  reducers: {
    // upsertUser: (state, action: PayloadAction<FederatedUser>) => {
    //   requestAnimationFrame(() => store.dispatch(upsertUserData(action.payload)));
    //   usersAdapter.upsertOne(state, action.payload);
    // },
    // removeUser: usersAdapter.removeOne,
    resetUsers: (state, action: PayloadAction<{ serverHost: string | undefined }>) => {
      if (!action.payload.serverHost) return;

      const userIdsToRemove = state.ids
        .filter(id => parseFederatedId(id as string).serverHost === action.payload.serverHost);
      usersAdapter.removeMany(state, userIdsToRemove);

      state.failedUsernames[action.payload.serverHost] = [];
      state.failedUserIds = state.failedUserIds.filter(id => parseFederatedId(id).serverHost !== action.payload.serverHost);

      delete state.userPages.values[action.payload.serverHost];
      delete state.pagesStatus.values[action.payload.serverHost];

      setTimeout(() => {
        store.dispatch(resetUserPosts(action.payload));
        store.dispatch(resetUserEvents(action.payload));
      }, 1);
    },
    resetUserEvents: (state, action: PayloadAction<{ serverHost: string | undefined }>) => {
      if (!action.payload.serverHost) return;

      Object.keys(state.idOccasions)
        .filter(id => parseFederatedId(id).serverHost === action.payload.serverHost)
        .forEach(id => delete state.idOccasions[id]);
    },
    resetUserPosts: (state, action: PayloadAction<{ serverHost: string | undefined }>) => {
      if (!action.payload.serverHost) return;

      Object.keys(state.idPosts)
        .filter(id => parseFederatedId(id).serverHost === action.payload.serverHost)
        .forEach(id => delete state.idPosts[id]);
      Object.keys(state.idReplies)
        .filter(id => parseFederatedId(id).serverHost === action.payload.serverHost)
        .forEach(id => delete state.idReplies[id]);
    },
  },
  extraReducers: (builder) => {
    function accountUserId(action: PayloadAction<any, any, { arg: AccountOrServer }>) {
      return federatedEntityId(action.meta.arg.account!.user, action);
    }
    builder.addCase(loadUsersPage.pending, (state, action) => {
      setFederated(state.pagesStatus, action, "loading");
    });
    builder.addCase(loadUsersPage.fulfilled, (state, action) => {
      setFederated(state.pagesStatus, action, "loaded");
      usersAdapter.upsertMany(state, federatedEntities(action.payload.users, action));

      const userIds = action.payload.users.map(u => federatedEntityId(u, action));
      const page = action.meta.arg.page ?? 0;
      const listingType = action.meta.arg.listingType ?? defaultUserListingType;

      const userPages = getFederated(state.userPages, action);
      if (!userPages[listingType]) userPages[listingType] = [];
      userPages[listingType]![page] = userIds;
      setFederated(state.userPages, action, userPages);

      // Update the users in any relevant accounts.
      const server = action.meta.arg.server!;

      setTimeout(() => {
        for (const user of action.payload.users) {
          store.dispatch(upsertUserData({ server, user }));
        }
      }, 1);
    });
    builder.addCase(loadUsersPage.rejected, (state, action) => {
      setFederated(state.pagesStatus, action, "errored");
    });
    [loadUser, loadUsername, updateUser].forEach((loader) => {
      builder.addCase(loader.pending, (_state) => { });
      builder.addCase(loader.fulfilled, (state, action) => {
        const user = action.payload;
        usersAdapter.upsertOne(state, { ...federatedEntity(user, action), hasAdvancedData: true });
        const usernameIds = getFederated(state.usernameIds, action);
        usernameIds[action.payload.username.split('@')[0]!] = federatedEntityId(user, action);
        setFederated(state.usernameIds, action, usernameIds);

        // Update the user in any relevant accounts.
        const server = action.meta.arg.server!;
        setTimeout(() => {
          store.dispatch(upsertUserData({ server, user }));
        }, 1);
      });
      builder.addCase(loader.rejected, (state, action) => {
        const requestUserId = loader == loadUser
          ? federateId((action.meta.arg as LoadUser).userId, action)
          : undefined;
        if (loader === loadUsername) {
          const failedUsernames = getFederated(state.failedUsernames, action);
          const updatedFailedUsernames = [...failedUsernames, (action.meta.arg as LoadUsername).username];
          setFederated(state.failedUsernames, action, updatedFailedUsernames);
        } else if (requestUserId && !state.failedUserIds.includes(requestUserId)) {
          // debugger;
          state.failedUserIds = [...state.failedUserIds, requestUserId];
        }
      });
    });

    builder.addCase(deleteUser.fulfilled, (state, action) => {
      // Update the user in any relevant accounts.
      const server = action.meta.arg.server!;
      const user = action.meta.arg as User;
      setTimeout(() => {
        store.dispatch(notifyUserDeleted({ server, user }));
      }, 1);
    });
    builder.addCase(loadUserPosts.fulfilled, (state, action) => {
      const posts = federatedEntities(action.payload.posts, action);
      const newPostIds = new Set(posts.map(federatedId));
      const userId = federateUserId(action);
      const updatedUserPostIds = state.idPosts[userId]
        ?.filter((p) => !newPostIds.has(p))
        || [];
      updatedUserPostIds.push(...newPostIds);
      state.idPosts[userId] = updatedUserPostIds;
    });
    builder.addCase(createPost.fulfilled, (state, action) => {
      const serverUserId = action.payload.author?.userId;
      if (!serverUserId) return;

      const userId = federateId(serverUserId, action);
      const postId = federatedId(federatedEntity(action.payload, action));
      const currentUserPosts = state.idPosts[userId];
      if (!currentUserPosts) return;

      state.idPosts[userId] = [postId, ...currentUserPosts];
    });
    builder.addCase(createEvent.fulfilled, (state, action) => {
      const serverUserId = action.payload.post?.author?.userId;
      if (!serverUserId) return;

      const userId = federateId(serverUserId, action);
      // debugger;
      // console.log('state.idOccasions[userId]', state.idOccasions[userId]);

      const oldOccasionIds = state.idOccasions[userId]?.map(id => id);
      if (!oldOccasionIds) return;

      const occasionIds = action.payload.occasions.map(occasion => federateId(occasion.id, action));
      const newOccasionIds = [...occasionIds, ...oldOccasionIds];
      // console.log('UserState createEvent.fulfilled', userId, occasionIds, oldOccasionIds, newOccasionIds);
      // debugger;
      state.idOccasions[userId] = newOccasionIds;
    });
    builder.addCase(loadUserReplies.fulfilled, (state, action) => {
      const replies = federatedEntities(action.payload.posts, action);
      const newPostIds = new Set(replies.map(federatedId));
      const updatedUserReplyIds = state.idReplies[federateUserId(action)]
        ?.filter((p) => !newPostIds.has(p))
        || [];
      updatedUserReplyIds.push(...newPostIds);
      state.idReplies[federateUserId(action)] = updatedUserReplyIds;
    });
    builder.addCase(loadUserEvents.fulfilled, (state, action) => {
      const events = federatedEntities(action.payload.events, action);
      const userId = federateUserId(action);
      const newOccasionIds = new Set(events.map(e => federateId(e.occasions[0]!.id, action)));
      const updatedUserOccasionIds = state.idOccasions[userId]
        ?.filter((p) => !newOccasionIds.has(p))
        || [];
      updatedUserOccasionIds.push(...newOccasionIds);
      state.idOccasions[userId] = updatedUserOccasionIds;
    });
    builder.addCase(followUnfollowUser.pending, (state, action) => {
      lockUser(state, federateUserId(action));
    });
    builder.addCase(followUnfollowUser.rejected, (state, action) => {
      unlockUser(state, federateUserId(action));
    });
    builder.addCase(followUnfollowUser.fulfilled, (state, action) => {
      unlockUser(state, federateUserId(action));
      let user = selectors.selectById(state, federateId(federateUserId(action), action))!;
      let currentUser = selectors.selectById(state, accountUserId(action));
      if (action.meta.arg.follow) {
        const result = action.payload as Follow;
        if (passes(result.targetUserModeration)) {
          user = { ...user, followerCount: (user.followerCount || 0) + 1 };
          if (currentUser) {
            currentUser = { ...currentUser, followingCount: (currentUser.followingCount || 0) + 1 };
          }
        }
        user = { ...user, currentUserFollow: result };
      } else {
        if (passes(user.currentUserFollow?.targetUserModeration)) {
          user = { ...user, followerCount: (user.followerCount || 0) - 1 };
          if (currentUser) {
            currentUser = { ...currentUser, followingCount: (currentUser.followingCount || 0) - 1 };
          }
        }
        user = { ...user, currentUserFollow: undefined };
      }
      usersAdapter.upsertOne(state, user);
      if (currentUser) {
        usersAdapter.upsertOne(state, currentUser);
      }
    });

    builder.addCase(respondToFollowRequest.pending, (state, action) => {
      lockUser(state, federateUserId(action));
    });
    builder.addCase(respondToFollowRequest.rejected, (state, action) => {
      unlockUser(state, federateUserId(action));
    });
    builder.addCase(respondToFollowRequest.fulfilled, (state, action) => {
      unlockUser(state, federateUserId(action));
      let user = selectors.selectById(state, federateUserId(action))!;
      if (action.meta.arg.accept) {
        const result = action.payload as Follow;
        user = { ...user, followingCount: (user.followingCount || 0) + 1, targetCurrentUserFollow: result };
        let currentUser = selectors.selectById(state, accountUserId(action));
        if (currentUser) {
          currentUser = { ...currentUser, followerCount: (currentUser.followerCount || 0) + 1 };
          usersAdapter.upsertOne(state, currentUser);
        }
      } else {
        user = { ...user, targetCurrentUserFollow: undefined };
      }
      usersAdapter.upsertOne(state, user);
    });

    builder.addCase(loadGroupMembers.fulfilled, (state, action) => {
      const federatedUsers = action.payload.members.map(
        m => m.user ? federatedEntity(m.user, action) : undefined
      ).filter(u => u) as FederatedUser[];
      usersAdapter.upsertMany(state, federatedUsers);
    });

    builder.addCase(federateAccounts.fulfilled, (state, action) => {
      const { account1, account2 } = action.meta.arg;
      const userId1 = federateId(account1.account!.user.id, account1.server?.host);
      const userId2 = federateId(account2.account!.user.id, account2.server?.host);
      const user1 = selectors.selectById(state, userId1);
      const user2 = selectors.selectById(state, userId2);

      if (user1) {
        usersAdapter.upsertOne(state, {
          ...user1,
          federatedProfiles: [
            ...(user1.federatedProfiles || []),
            {
              userId: account2.account!.user.id,
              host: account2.server!.host
            }],
        });
      }
      if (user2) {
        usersAdapter.upsertOne(state, {
          ...user2,
          federatedProfiles: [
            ...(user2.federatedProfiles || []),
            {
              userId: account1.account!.user.id,
              host: account1.server!.host
            }],
        });
      }
    });

    builder.addCase(defederateAccounts.fulfilled, (state, action) => {
      const { account1, account2, account2Profile } = action.meta.arg;
      const userId1 = federateId(account1.account!.user.id, account1.server?.host);
      const userId2 = federateId(account2Profile.userId, account2Profile.host);
      const user1 = selectors.selectById(state, userId1);
      const user2 = selectors.selectById(state, userId2);

      if (user1) {
        usersAdapter.upsertOne(state, {
          ...user1,
          federatedProfiles: user1.federatedProfiles.filter(p =>
            p.userId !== account2Profile.userId ||
            p.host !== account2Profile.host
          )
        });
      }
      if (user2) {
        usersAdapter.upsertOne(state, {
          ...user2,
          federatedProfiles: user2.federatedProfiles.filter(p =>
            p.userId !== account1.account!.user.id ||
            p.host !== account1.server!.host
          )
        });
      }
    });
  },
});

export const { resetUsers, resetUserEvents, resetUserPosts } = usersSlice.actions;

export const { selectAll: selectAllUsers, selectById: selectUserById } = selectors;
export const usersReducer = usersSlice.reducer;
export default usersReducer;


function lockUser(state: UsersState, userId: string) {
  state.mutatingUserIds = [userId, ...state.mutatingUserIds];
}
function unlockUser(state: UsersState, userId: string) {
  state.mutatingUserIds = state.mutatingUserIds.filter(u => u != userId);
}

export function isUserLocked(state: UsersState, userId: string): boolean {
  return state.mutatingUserIds.includes(userId);
}
