// Rellm's service worker. Currently only used for Web Push notifications -- see
// `Shared.AccountsPanel`'s "Enable notifications", `index.html`'s subscribeToPush/pushSubscribed/
// unsubscribeFromPush port handlers, and `backend/src/web_push` (which sends the pushes this
// reacts to). Registered unconditionally at page load (see index.html), scoped to wherever this
// file itself is served from (`/` or `/elm/`, matching `rellmBasePath`) -- a no-op until a user
// actually opts into notifications.

// Push payloads arrive already decrypted by the browser (Web Push's own encryption, handled
// before this event fires) as the plaintext JSON `backend/src/web_push`'s `PushPayload` sends:
// `{ title, body, url?, icon?, host? }` -- `url` (a full `https://<frontend_host>/messages?...#message-<id>`
// deep link straight to the Message, see `web_push::notification_url`), `icon` (the sender's own
// avatar, see `web_push::build_icon_url` -- absent for inbound email, which has no local sender),
// and `host` (the same `frontend_host`, plain) are only present if the server has a configured
// `ExternalCdnConfig.frontend_host` to build them from. `icon` falls back to the site's own
// favicon, same as before this payload ever carried one. `url` is stashed on the notification's
// own `data` (not just closed over here) since `notificationclick` below fires as a *separate*
// event, with no other way to recover which push it's reacting to.
//
// Also `postMessage`s every open client with `{ type: 'push-received', host }` -- picked up by
// `index.html`'s `navigator.serviceWorker` listener and forwarded to `Ports.pushMessageReceived`,
// so an already-open tab refreshes that server's Messages (`MessagingPanel`/`Pages.Messages`, see
// `Components.Pages.MessagesPage.PushNotificationReceived`) instead of only finding out once the
// notification itself is clicked.
self.addEventListener('push', function (event) {
  var payload = { title: 'Rellm', body: 'You have a new message.' };
  if (event.data) {
    try {
      payload = event.data.json();
    } catch (e) {
      payload.body = event.data.text();
    }
  }
  event.waitUntil(
    Promise.all([
      self.registration.showNotification(payload.title || 'Rellm', {
        body: payload.body || '',
        icon: payload.icon || '/favicon.png',
        badge: '/favicon.png',
        data: { url: payload.url || '/' }
      }),
      clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (windowClients) {
        windowClients.forEach(function (client) {
          client.postMessage({ type: 'push-received', host: payload.host || null });
        });
      })
    ])
  );
});

// Navigates an already-open Rellm tab straight to the Message the notification was about (a
// full navigation, not an in-app route change -- `WindowClient.navigate()` has no way to hand
// control back to the already-running Elm app's own router), falling back to just focusing it if
// navigation isn't supported (e.g. `client.navigate` is missing in some Safari versions), or
// opening a fresh tab there if no Rellm tab is open at all.
function isSameOrigin(a, b) {
  try {
    return new URL(a, self.location.href).origin === new URL(b, self.location.href).origin;
  } catch (e) {
    return true;
  }
}

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var targetUrl = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (windowClients) {
      for (var i = 0; i < windowClients.length; i++) {
        var client = windowClients[i];
        if (!('focus' in client)) { continue; }
        // A notification for a *different* server than the one this tab is on (one browser push
        // subscription can be shared by every server using the same VAPID key) -- `navigate()`
        // can't cross origins, so hand the URL to the app (`index.html` forwards it to
        // `Ports.pushNotificationClicked`, `Shared.PushNotificationLink` turns it into an in-app
        // route) and just focus the tab.
        if (!isSameOrigin(targetUrl, client.url)) {
          client.postMessage({ type: 'notification-clicked', url: targetUrl });
          return client.focus();
        }
        if ('navigate' in client) {
          return client.navigate(targetUrl).then(
            function (navigatedClient) { return (navigatedClient || client).focus(); },
            function () { return client.focus(); }
          );
        }
        return client.focus();
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});
