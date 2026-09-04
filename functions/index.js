const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Escapes HTML entities to prevent XSS in dynamic meta tags
 */
function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/**
 * Cloud Function to generate dynamic OpenGraph link previews for WhatsApp & Social Media
 */
exports.sharePreview = functions.https.onRequest(async (req, res) => {
  try {
    const rawPath = req.path || "/";
    const pathSegments = rawPath.split("/").filter(Boolean);
    const query = req.query || {};

    const routeType = pathSegments[0] || "portal"; // portal, c, p, event, ep, share
    const routeIdentifier = pathSegments[1] || query.event || query.company || "";
    const eventIdParam = query.event || "";

    let companyName = "تسهيل جيفت";
    let eventName = "منظومة إدارة العروض والهدايا الترويجية";
    let companyLogoUrl = "https://tashil-gift.web.app/icons/Icon-512.png";
    let welcomeDesc = "Tashil Gift - Smart Multi-Company Promotion & Validation Platform by Switch Point";
    let isManagerPortal = routeType === "portal" || routeType === "p" || routeType === "ep";

    // 1. Try resolving event from Firestore by ID if available
    let resolvedEvent = null;

    if (eventIdParam) {
      const eventDoc = await db.collection("events").doc(eventIdParam).get();
      if (eventDoc.exists) {
        resolvedEvent = eventDoc.data();
      }
    }

    if (!resolvedEvent && routeIdentifier) {
      // Check if identifier is an event ID
      const eventDoc = await db.collection("events").doc(routeIdentifier).get();
      if (eventDoc.exists) {
        resolvedEvent = eventDoc.data();
      }
    }

    // 2. If not found by event ID, search by companySlug or targetCompany in events collection
    if (!resolvedEvent && routeIdentifier) {
      const cleanSlug = routeIdentifier.toLowerCase();
      const slugQuery = await db
        .collection("events")
        .where("companySlug", "==", cleanSlug)
        .limit(1)
        .get();

      if (!slugQuery.empty) {
        resolvedEvent = slugQuery.docs[0].data();
      }
    }

    // 3. Extract resolved brand information
    if (resolvedEvent) {
      companyName = resolvedEvent.targetCompany || resolvedEvent.companyName || companyName;
      eventName = resolvedEvent.eventName || eventName;
      if (resolvedEvent.companyLogoUrl && resolvedEvent.companyLogoUrl.trim().length > 0) {
        companyLogoUrl = resolvedEvent.companyLogoUrl.trim();
      }
      if (resolvedEvent.welcomeMessage && resolvedEvent.welcomeMessage.trim().length > 0) {
        welcomeDesc = resolvedEvent.welcomeMessage.trim();
      } else if (resolvedEvent.welcomeTitle && resolvedEvent.welcomeTitle.trim().length > 0) {
        welcomeDesc = resolvedEvent.welcomeTitle.trim();
      }
    } else if (query.companyName) {
      companyName = query.companyName;
    }

    if (query.logo) {
      companyLogoUrl = query.logo;
    }

    // 4. Construct rich title and description
    let pageTitle = "";
    let pageDescription = "";

    if (isManagerPortal) {
      pageTitle = `${companyName} • بوابة الشريك | Tashil Gift`;
      pageDescription = `منظومة إدارة ومتابعة الحملات الترويجية والهدايا لشركة ${companyName}`;
    } else {
      pageTitle = `${eventName} (${companyName}) | Tashil Gift`;
      pageDescription = welcomeDesc;
    }

    const escapedTitle = escapeHtml(pageTitle);
    const escapedDesc = escapeHtml(pageDescription);
    const escapedLogo = escapeHtml(companyLogoUrl);

    // Set cache control for performance
    res.set("Cache-Control", "public, max-age=300, s-maxage=600");
    res.set("Content-Type", "text/html; charset=utf-8");

    const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapedTitle}</title>
  <meta name="description" content="${escapedDesc}">

  <!-- iOS meta tags & icons -->
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="${escapedTitle}">
  <link rel="apple-touch-icon" href="/icons/Icon-192.png">

  <!-- Favicon -->
  <link rel="icon" type="image/svg+xml" href="/favicon.svg"/>
  <link rel="icon" type="image/png" href="/favicon.png"/>

  <!-- Open Graph / WhatsApp / Facebook -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Tashil Gift">
  <meta property="og:title" content="${escapedTitle}">
  <meta property="og:description" content="${escapedDesc}">
  <meta property="og:image" content="${escapedLogo}">
  <meta property="og:image:secure_url" content="${escapedLogo}">
  <meta property="og:image:alt" content="${escapedTitle}">
  <meta property="og:image:width" content="600">
  <meta property="og:image:height" content="600">

  <!-- Twitter Card -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapedTitle}">
  <meta name="twitter:description" content="${escapedDesc}">
  <meta name="twitter:image" content="${escapedLogo}">

  <link rel="manifest" href="/manifest.json">
</head>
<body>
  <script>
    // Handle legacy hash URLs (e.g. /#/c/512?event=...) by converting them to clean path URLs before Flutter boots
    (function() {
      var hash = window.location.hash;
      if (hash && (hash.startsWith('#/') || hash.startsWith('#!/'))) {
        var cleanPath = hash.replace(/^#[!]?/, '');
        if (cleanPath.startsWith('/')) {
          window.history.replaceState(null, '', cleanPath);
        }
      }
    })();
  </script>
  <script>
    // Proactively check and update service worker to avoid stale client-side caches
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(function(registrations) {
        for (var i = 0; i < registrations.length; i++) {
          registrations[i].update();
        }
      });
    }
  </script>
  <!-- Flutter Web Bootstrap -->
  <script src="/flutter_bootstrap.js" async></script>
</body>
</html>`;

    res.status(200).send(html);
  } catch (error) {
    console.error("Error generating share preview:", error);
    // Graceful fallback to static Flutter web SPA
    res.redirect("/index.html");
  }
});
