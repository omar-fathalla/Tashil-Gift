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
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

/**
 * Resolves event document from Firestore by eventId or companySlug
 */
async function resolveEvent(db, eventIdParam, routeIdentifier) {
  if (eventIdParam) {
    const eventDoc = await db.collection("events").doc(eventIdParam).get();
    if (eventDoc.exists) return eventDoc.data();
  }

  if (routeIdentifier) {
    const directDoc = await db.collection("events").doc(routeIdentifier).get();
    if (directDoc.exists) return directDoc.data();

    const cleanSlug = routeIdentifier.toLowerCase();
    const slugQuery = await db
      .collection("events")
      .where("companySlug", "==", cleanSlug)
      .limit(1)
      .get();

    if (!slugQuery.empty) return slugQuery.docs[0].data();
  }

  return null;
}

/**
 * Extracts and formats metadata for social share preview
 */
function extractPreviewMetadata(resolvedEvent, query, isManagerPortal) {
  let companyName = "تسهيل جيفت";
  let eventName = "منظومة إدارة العروض والهدايا الترويجية";
  let companyLogoUrl = "https://tashil-gift.web.app/icons/Icon-512.png";
  let welcomeDesc = "Tashil Gift - Smart Multi-Company Promotion & Validation Platform by Switch Point";

  if (resolvedEvent) {
    companyName = resolvedEvent.targetCompany || resolvedEvent.companyName || companyName;
    eventName = resolvedEvent.eventName || eventName;
    if (resolvedEvent.companyLogoUrl?.trim()) {
      companyLogoUrl = resolvedEvent.companyLogoUrl.trim();
    }
    const welcome = resolvedEvent.welcomeMessage?.trim() || resolvedEvent.welcomeTitle?.trim();
    if (welcome) {
      welcomeDesc = welcome;
    }
  } else if (query.companyName) {
    companyName = query.companyName;
  }

  if (query.logo) {
    companyLogoUrl = query.logo;
  }

  let pageTitle = "";
  let pageDescription = "";

  if (isManagerPortal) {
    pageTitle = `${companyName} • بوابة الشريك | Tashil Gift`;
    pageDescription = `منظومة إدارة ومتابعة الحملات الترويجية والهدايا لشركة ${companyName}`;
  } else {
    pageTitle = `${eventName} (${companyName}) | Tashil Gift`;
    pageDescription = welcomeDesc;
  }

  return {
    pageTitle,
    pageDescription,
    companyLogoUrl,
  };
}

/**
 * Builds HTML page template with rich OpenGraph / Twitter meta tags
 */
function buildPreviewHtml({ pageTitle, pageDescription, companyLogoUrl }) {
  const escapedTitle = escapeHtml(pageTitle);
  const escapedDesc = escapeHtml(pageDescription);
  const escapedLogo = escapeHtml(companyLogoUrl);

  return `<!DOCTYPE html>
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
    const isManagerPortal = routeType === "portal" || routeType === "p" || routeType === "ep";

    const resolvedEvent = await resolveEvent(db, eventIdParam, routeIdentifier);
    const meta = extractPreviewMetadata(resolvedEvent, query, isManagerPortal);

    // Set cache control for performance
    res.set("Cache-Control", "public, max-age=300, s-maxage=600");
    res.set("Content-Type", "text/html; charset=utf-8");

    res.status(200).send(buildPreviewHtml(meta));
  } catch (error) {
    console.error("Error generating share preview:", error);
    // Graceful fallback to static Flutter web SPA
    res.redirect("/index.html");
  }
});

const { analyzeReceiptWithGateway } = require("./gemini_gateway");

/**
 * Cloud Function: analyzeReceipt
 * Proxies and accelerates receipt verification with LRU caching, rate limiting, and exponential backoff retry.
 */
exports.analyzeReceipt = functions.https.onCall(async (data, context) => {
  const { campaignId, imagePayload, forceRefresh } = data || {};
  if (!imagePayload) {
    throw new functions.https.HttpsError("invalid-argument", "imagePayload is required");
  }

  try {
    return await analyzeReceiptWithGateway({
      db,
      campaignId,
      imagePayload,
      forceRefresh: forceRefresh === true,
      callGeminiModelFn: async ({ branches, products, imageHash }) => {
        // Mock / placeholder implementation for standalone function invocation
        return {
          isValid: true,
          receiptNumber: "EXT-" + imageHash.substring(0, 8).toUpperCase(),
          storeChainDetected: "Gomla Market",
          branchDetected: branches[0] || "Main Branch",
          isBranchMatched: true,
          message: "تم التحقق بنجاح من الفاتورة عبر مسار Gemini Gateway",
        };
      },
    });
  } catch (err) {
    console.error("Gemini gateway analysis failed:", err);
    if (err.code === 429) {
      throw new functions.https.HttpsError("resource-exhausted", err.message);
    }
    throw new functions.https.HttpsError("internal", err.message);
  }
});
